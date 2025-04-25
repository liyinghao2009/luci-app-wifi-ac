// 设备管理相关 JS

function fetchDeviceList() {
  fetch(L.env.cgiBase + '/admin/network/wifi_ac/api/device_list')
    .then(r => r.json())
    .then(data => renderDeviceTable(data.devices || []));
}

function renderDeviceTable(devices) {
  // 移动端适配：表格容器横向滚动
  let tableWrap = document.getElementById("device-table-wrap");
  if (tableWrap) tableWrap.style.overflowX = "auto";
  const tbody = document.querySelector("#device-table tbody");
  tbody.innerHTML = "";
  let vendors = {}, firmwares = {};
  devices.forEach(dev => {
    vendors[dev.vendor] = true;
    firmwares[dev.firmware] = true;
    let logo = dev.vendor ? dev.vendor.toLowerCase() : 'unknown';
    let logoSrc = `/luci-static/resources/wifi-ac/img/${logo}.png`;
    // LOGO图片onerror兜底default_vendor.png
    let tr = document.createElement("tr");
    tr.innerHTML = `
      <td><input type="checkbox" class="dev-select" value="${dev.mac}"></td>
      <td>
        <img src="${logoSrc}" 
             style="height:20px;vertical-align:middle;border-radius:3px;background:#fff;padding:2px;border:1px solid var(--cbi-border-color,#e5e5e5);object-fit:contain;"
             onerror="this.onerror=null;this.src='/luci-static/resources/wifi-ac/img/default_vendor.png'">
        <span style="margin-left:4px;">${dev.vendor || ''}</span>
      </td>
      <td>${dev.model || ''}</td>
      <td><span style="font-family:monospace;color:var(--cbi-accent-color,#409eff);">${dev.mac || ''}</span></td>
      <td>${dev.ip || ''}</td>
      <td>
        <span style="
          display:inline-block;
          min-width:48px;
          border-radius:12px;
          padding:2px 10px;
          font-size:13px;
          background:${dev.status=='online' ? 'var(--badge-success-bg,#67c23a)' : 'var(--badge-default-bg,#dcdfe6)'};
          color:${dev.status=='online' ? 'var(--badge-success-color,#fff)' : 'var(--badge-default-color,#888)'};
        ">${dev.status || ''}</span>
      </td>
      <td>
        <progress value="${dev.cpu}" max="100" style="accent-color:var(--cbi-accent-color,#409eff);height:10px;"></progress>
        <span style="margin-left:4px;">${dev.cpu}%</span>
      </td>
      <td>
        <progress value="${dev.mem}" max="100" style="accent-color:var(--cbi-warning-color,#e6a23c);height:10px;"></progress>
        <span style="margin-left:4px;">${dev.mem}%</span>
      </td>
      <td>${dev.clients_24g !== undefined ? dev.clients_24g : ''}</td>
      <td>${dev.clients_5g !== undefined ? dev.clients_5g : ''}</td>
      <td>${dev.firmware || ''}</td>
      <td>
        <button class="detail-btn" data-mac="${dev.mac}" style="
          background:var(--cbi-accent-color,#409eff);
          color:#fff;
          border:none;
          border-radius:3px;
          padding:3px 12px;
          cursor:pointer;
          transition:background 0.2s;"
          onmouseover="this.style.background='var(--cbi-accent-hover,#66b1ff)'"
          onmouseout="this.style.background='var(--cbi-accent-color,#409eff)'"
        >${_('详情')}</button>
        <button class="template-btn" data-mac="${dev.mac}" data-vendor="${dev.vendor}" style="
          margin-left:4px;
          background:#f5a623;
          color:#fff;
          border:none;
          border-radius:3px;
          padding:3px 8px;
          cursor:pointer;"
        >${_('模板')}</button>
      </td>
    `;
    tbody.appendChild(tr);
  });

  // 填充厂商筛选
  const vendorSel = document.getElementById("vendor-filter");
  vendorSel.innerHTML = '<option value="">全部厂商</option>';
  Object.keys(vendors).forEach(v => {
    if (v) vendorSel.innerHTML += `<option value="${v}">${v}</option>`;
  });
  // 填充固件筛选
  const fwSel = document.getElementById("firmware-filter");
  fwSel.innerHTML = '<option value="">全部固件</option>';
  Object.keys(firmwares).forEach(fw => {
    if (fw) fwSel.innerHTML += `<option value="${fw}">${fw}</option>`;
  });

  // 补充：设备添加表单厂商/型号下拉（需后端接口支持）
  if (document.getElementById("add-vendor")) {
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/vendors")
      .then(r => r.json())
      .then(list => {
        let sel = document.getElementById("add-vendor");
        sel.innerHTML = '<option value="">请选择厂商</option>' + (list || []).map(v => `<option value="${v}">${v}</option>`).join("");
      });
  }
  if (document.getElementById("add-model")) {
    document.getElementById("add-vendor").onchange = function() {
      let vendor = this.value;
      fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/models?vendor=" + encodeURIComponent(vendor))
        .then(r => r.json())
        .then(list => {
          let sel = document.getElementById("add-model");
          sel.innerHTML = '<option value="">请选择型号</option>' + (list || []).map(m => `<option value="${m}">${m}</option>`).join("");
        });
    };
  }
}

function getSelectedMacs() {
  return Array.from(document.querySelectorAll(".dev-select:checked")).map(cb => cb.value);
}

// 细粒度权限校验（示例，window.L.env.permissions 由后端注入）
function hasPermission(action) {
  // 支持操作类型、角色等更细粒度控制
  if (!window.L.env.permissions) return true;
  if (typeof action === "string") return window.L.env.permissions.includes(action);
  if (Array.isArray(action)) return action.some(a => window.L.env.permissions.includes(a));
  return false;
}

document.addEventListener("DOMContentLoaded", function() {
  fetchDeviceList();
  document.getElementById("search").addEventListener("input", function() {
    // 多条件组合筛选
    function filterTable() {
      let kw = document.getElementById("search").value.trim().toLowerCase();
      let vendor = document.getElementById("vendor-filter").value;
      let status = document.getElementById("status-filter").value;
      let firmware = document.getElementById("firmware-filter").value;
      Array.from(document.querySelectorAll("#device-table tbody tr")).forEach(tr => {
        let txt = tr.innerText.toLowerCase();
        let show = (!kw || txt.includes(kw))
          && (!vendor || tr.innerHTML.includes(vendor))
          && (!status || tr.innerHTML.includes(status))
          && (!firmware || tr.innerHTML.includes(firmware));
        tr.style.display = show ? "" : "none";
      });
    }
    document.getElementById("search").addEventListener("input", filterTable);
    document.getElementById("vendor-filter").addEventListener("change", filterTable);
    document.getElementById("status-filter").addEventListener("change", filterTable);
    document.getElementById("firmware-filter").addEventListener("change", filterTable);
  });

  document.getElementById("select-all").addEventListener("change", function() {
    document.querySelectorAll(".dev-select").forEach(cb => cb.checked = this.checked);
  });

  document.getElementById("batch-reboot").addEventListener("click", function() {
    if (!hasPermission("device_batch_reboot")) return alert(_("无权限执行该操作"));
    let macs = getSelectedMacs();
    if (!macs.length) return alert(_("请选择设备"));
    fetch(L.env.cgiBase + '/admin/network/wifi_ac/api/device_batch', {
      method: "POST",
      body: new URLSearchParams({action: "reboot", macs: macs.join(",")})
    }).then(r => r.json()).then(res => {
      alert(_("重启结果: ") + JSON.stringify(res));
      showBatchProgress(res);
    });
  });

  document.getElementById("batch-upgrade").addEventListener("click", function() {
    if (!hasPermission("device_batch_upgrade")) return alert(_("无权限执行该操作"));
    let macs = getSelectedMacs();
    if (!macs.length) return alert(_("请选择设备"));
    let firmware = prompt(_("请输入要升级的固件版本/文件名"));
    if (!firmware) return;
    fetch(L.env.cgiBase + '/admin/network/wifi_ac/api/device_batch', {
      method: "POST",
      body: new URLSearchParams({action: "upgrade", macs: macs.join(","), firmware})
    }).then(r => r.json()).then(res => {
      alert(_("升级结果: ") + JSON.stringify(res));
      showBatchProgress(res);
    });
  });

  document.getElementById("batch-sync").addEventListener("click", function() {
    if (!hasPermission("device_batch_sync")) return alert(_("无权限执行该操作"));
    let macs = getSelectedMacs();
    if (!macs.length) return alert(_("请选择设备"));
    fetch(L.env.cgiBase + '/admin/network/wifi_ac/api/device_batch', {
      method: "POST",
      body: new URLSearchParams({action: "sync", macs: macs.join(",")})
    }).then(r => r.json()).then(res => {
      alert(_("同步结果: ") + JSON.stringify(res));
      showBatchProgress(res);
    });
  });

  document.getElementById("show-add-device").addEventListener("click", function() {
    document.getElementById("add-device-form").style.display = "block";
  });

  document.getElementById("cancel-add-device").addEventListener("click", function() {
    document.getElementById("add-device-form").style.display = "none";
  });

  document.getElementById("add-device-btn").addEventListener("click", function() {
    let mac = document.getElementById("add-mac").value.trim();
    let ip = document.getElementById("add-ip").value.trim();
    let vendor = document.getElementById("add-vendor").value.trim();
    let model = document.getElementById("add-model").value.trim();
    let firmware = document.getElementById("add-firmware").value.trim();
    // 简单格式校验
    if (!/^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(mac)) return alert(_("MAC格式错误"));
    if (!/^(\d{1,3}\.){3}\d{1,3}$/.test(ip)) return alert(_("IP格式错误"));
    if (!mac || !ip) return alert(_("MAC和IP必填"));
    // 新增：重复检测（前端简单检测，后端仍需兜底）
    fetch(L.env.cgiBase + '/admin/network/wifi_ac/api/device_list')
      .then(r => r.json())
      .then(data => {
        let exists = (data.devices || []).some(d => d.mac === mac || d.ip === ip);
        if (exists) {
          alert(_("MAC或IP已存在，请勿重复添加"));
          return;
        }
        fetch(L.env.cgiBase + '/admin/network/wifi_ac/api/device_add', {
          method: "POST",
          body: new URLSearchParams({mac, ip, vendor, model, firmware})
        }).then(r => r.json()).then(res => {
          alert(_(res.msg));
          if (res.code === 0) {
            document.getElementById("add-device-form").style.display = "none";
            fetchDeviceList();
          }
        });
      });
  });

  document.querySelector("#device-table").addEventListener("click", function(e) {
    if (e.target.classList.contains("detail-btn")) {
      let mac = e.target.dataset.mac;
      fetch(L.env.cgiBase + '/admin/network/wifi_ac/api/device_detail?mac=' + encodeURIComponent(mac))
        .then(r => r.json())
        .then(detail => {
          showDeviceDetailModal(detail);
        });
    }
    if (e.target.classList.contains("template-btn")) {
      let mac = e.target.dataset.mac;
      let vendor = e.target.dataset.vendor;
      fetch(L.env.cgiBase + '/admin/network/wifi_ac/api/device_template?vendor=' + encodeURIComponent(vendor) + '&mac=' + encodeURIComponent(mac))
        .then(r => r.json())
        .then(tpl => {
          if (confirm(_("应用模板: ") + JSON.stringify(tpl))) {
            fetch(L.env.cgiBase + '/admin/network/wifi_ac/api/device_template?vendor=' + encodeURIComponent(vendor) + '&mac=' + encodeURIComponent(mac) + '&apply=1')
              .then(r => r.json())
              .then(() => alert(_("模板下发成功")));
          }
        });
    }
  });

  // WebSocket实时状态（需后端支持ws接口）
  if ("WebSocket" in window) {
    try {
      let ws = new WebSocket("ws://" + location.host + L.env.cgiBase + "/admin/network/wifi_ac/api/ws_status");
      ws.onmessage = function(evt) {
        // 解析推送数据，刷新表格
        fetchDeviceList();
      };
    } catch (e) {}
  }

  // WebSocket实时状态（新版接口，推送数据格式为{devices:[...] }）
  if ("WebSocket" in window) {
    try {
      const ws = new WebSocket("ws://" + location.host + "/ws/wifi-ac/status");
      ws.onmessage = (event) => {
        const data = JSON.parse(event.data);
        if (data.devices && Array.isArray(data.devices)) {
          data.devices.forEach(device => {
            // 你可以自定义 updateDeviceStatus 方法以刷新表格行
            updateDeviceStatus(device.mac, device.status, device.reason, device.signal, device.cpu, device.mem);
          });
        }
      };
    } catch (e) {}
  }

  startStatusWebSocket();
  addTrendChartControls();

  document.getElementById("discover-udp").onclick = function() {
    let progress = document.getElementById("discover-progress");
    progress.textContent = "UDP发现中...";
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/device_add?discover=1")
      .then(r => r.json()).then(res => {
        progress.textContent = "发现" + (res.devices ? res.devices.length : 0) + "台设备";
        handleDiscoverResult(res);
      });
  };

  document.getElementById("discover-mdns").onclick = function() {
    let progress = document.getElementById("discover-progress");
    progress.textContent = "mDNS发现中...";
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/device_add?mdns=1")
      .then(r => r.json()).then(res => {
        progress.textContent = "发现" + (res.devices ? res.devices.length : 0) + "台设备";
        handleDiscoverResult(res);
      });
  };

  document.getElementById("discover-http").onclick = function() {
    let progress = document.getElementById("discover-progress");
    progress.textContent = "HTTP注册发现中...";
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/device_add?http=1")
      .then(r => r.json()).then(res => {
        progress.textContent = "发现" + (res.devices ? res.devices.length : 0) + "台设备";
        handleDiscoverResult(res);
      });
  };

});

// 刷新表格中某一行的所有数据
function updateDeviceStatus(mac, status, reason, signal, cpu, mem) {
  const rows = document.querySelectorAll("#device-table tbody tr");
  rows.forEach(tr => {
    if (tr.innerHTML.includes(mac)) {
      // 状态
      const statusTd = tr.querySelector("td:nth-child(6) span");
      if (statusTd) {
        statusTd.innerText = status || "";
        statusTd.style.background = status === "online"
          ? 'var(--badge-success-bg,#67c23a)'
          : 'var(--badge-default-bg,#dcdfe6)';
        statusTd.style.color = status === "online"
          ? 'var(--badge-success-color,#fff)'
          : 'var(--badge-default-color,#888)';
      }
      // 信号
      // 可扩展：tr.querySelector("td:nth-child(x)")...
      // CPU/内存
      if (typeof cpu !== "undefined") {
        let cpuBar = tr.querySelector("td:nth-child(7) progress");
        let cpuVal = tr.querySelector("td:nth-child(7) span");
        if (cpuBar) cpuBar.value = cpu;
        if (cpuVal) cpuVal.innerText = cpu + "%";
      }
      if (typeof mem !== "undefined") {
        let memBar = tr.querySelector("td:nth-child(8) progress");
        let memVal = tr.querySelector("td:nth-child(8) span");
        if (memBar) memBar.value = mem;
        if (memVal) memVal.innerText = mem + "%";
      }
      // 可根据 reason、signal 更新其它显示
    }
  });
}

function startStatusWebSocket() {
  let ws;
  function connect() {
    ws = new WebSocket("ws://" + location.host + "/ws/wifi-ac/status");
    ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.devices && Array.isArray(data.devices)) {
        data.devices.forEach(device => {
          updateDeviceStatus(device.mac, device.status, device.reason, device.signal, device.cpu, device.mem);
        });
      }
    };
    ws.onclose = () => {
      setTimeout(connect, 5000); // 断开后5秒重连
    };
    ws.onerror = () => {
      ws.close();
    };
  }
  connect();
}

// 趋势图自定义时间范围与导出入口（实际渲染见 optimization.js）
function addTrendChartControls() {
  let trendDiv = document.getElementById("trend-chart-controls");
  if (!trendDiv) {
    trendDiv = document.createElement("div");
    trendDiv.id = "trend-chart-controls";
    trendDiv.innerHTML = `
      <label>${_("起始时间")}<input type="datetime-local" id="trend-start"></label>
      <label>${_("结束时间")}<input type="datetime-local" id="trend-end"></label>
      <select id="trend-metric">
        <option value="load">${_("平均负载")}</option>
        <option value="signal">${_("平均信号")}</option>
        <option value="clients">${_("接入数")}</option>
      </select>
      <button id="trend-query">${_("查询")}</button>
      <button id="trend-export">${_("导出CSV")}</button>
    `;
    let chart = document.getElementById("trend-chart");
    if (chart) chart.parentNode.insertBefore(trendDiv, chart);
    document.getElementById("trend-query").onclick = function() {
      let start = document.getElementById("trend-start").value;
      let end = document.getElementById("trend-end").value;
      let metric = document.getElementById("trend-metric").value;
      if (window.updateTrendChart) window.updateTrendChart(start, end, metric);
    };
    document.getElementById("trend-export").onclick = function() {
      if (window.exportTrendChart) window.exportTrendChart();
    };
  }
}

// 功率调节控件细粒度适配（根据厂商/型号动态渲染控件和范围）
function renderTxPowerInput(vendor, model, mac, current) {
  fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/txpower_range?vendor=" + encodeURIComponent(vendor) + "&model=" + encodeURIComponent(model))
    .then(r => r.json())
    .then(range => {
      let box = document.getElementById("txpower-box-" + mac);
      if (!box) return;
      box.innerHTML = "";
      let input;
      // 细粒度适配：后端返回type/step/options等，前端动态渲染
      if (range.type === "select" && Array.isArray(range.options)) {
        input = document.createElement("select");
        range.options.forEach(opt => {
          let o = document.createElement("option");
          o.value = opt;
          o.innerText = opt + " dBm";
          if (String(opt) === String(current)) o.selected = true;
          input.appendChild(o);
        });
      } else if (range.type === "range") {
        input = document.createElement("input");
        input.type = "range";
        input.min = range.min;
        input.max = range.max;
        input.step = range.step;
        input.value = current || range.max;
      } else if (range.type === "number") {
        input = document.createElement("input");
        input.type = "number";
        input.min = range.min;
        input.max = range.max;
        input.step = range.step;
        input.value = current || range.max;
      } else {
        // fallback
        input = document.createElement("input");
        input.type = "number";
        input.value = current || "";
      }
      input.onchange = function() {
        fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/set_power/" + encodeURIComponent(mac) + "/" + encodeURIComponent(vendor) + "?model=" + encodeURIComponent(model), {
          method: "POST",
          body: input.value
        }).then(r => r.json()).then(res => {
          if(res.status !== "success") alert(res.message || _("设置失败"));
          document.getElementById("power-val-" + mac).innerText = input.value;
        });
      };
      box.appendChild(input);
    });
}

// 优化操作权限细粒度校验（后端API建议增加token/role参数，前端已做hasPermission判断，后端需配合）
function hasPermission(action) {
  // 示例：假设window.L.env.permissions为权限数组
  return !window.L.env.permissions || window.L.env.permissions.includes(action);
}

// 批量操作/模板应用失败详细展示与重试
function showBatchProgress(summary) {
  let el = document.getElementById("batch-progress");
  // 进度条
  let total = (summary.success || 0) + (summary.fail || 0);
  let percent = total ? Math.round((summary.success / total) * 100) : 0;
  el.innerHTML = `
    <div style="margin:8px 0;">
      <div style="background:#eee;width:100%;height:12px;border-radius:6px;overflow:hidden;">
        <div style="background:#67c23a;width:${percent}%;height:12px;"></div>
      </div>
      <span>${_("成功: ")}${summary.success} ${_("失败: ")}${summary.fail}</span>
    </div>
  `;
  // 详细失败原因与重试
  if (summary.fail > 0 && summary.detail) {
    el.innerHTML += "<br>" + _("失败设备:") + "<ul>" +
      Object.keys(summary.detail).map(mac => {
        let info = summary.detail[mac];
        let msg = typeof info === "object" ? (info.msg || info.error || JSON.stringify(info)) : info;
        return `<li>${mac}: ${msg} <button class="retry-btn" data-mac="${mac}">${_("重试")}</button></li>`;
      }).join("") + "</ul>";
    // 绑定重试事件
    el.querySelectorAll(".retry-btn").forEach(btn => {
      btn.onclick = function() {
        fetch(L.env.cgiBase + '/admin/network/wifi_ac/api/device_batch', {
          method: "POST",
          body: new URLSearchParams({action: summary.action || "reboot", macs: btn.dataset.mac})
        }).then(r => r.json()).then(res => {
          alert(_("重试结果: ") + JSON.stringify(res));
          showBatchProgress(res);
        });
      };
    });
  }
  // 模板批量应用详细失败原因
  if (summary.template_fail && Array.isArray(summary.template_fail)) {
    el.innerHTML += "<br>" + _("模板应用失败:") + "<ul>" +
      summary.template_fail.map(item =>
        `<li>${item.mac}: ${item.msg || item.error || item} <button class="retry-tpl-btn" data-mac="${item.mac}">${_("重试")}</button></li>`).join("") + "</ul>";
    el.querySelectorAll(".retry-tpl-btn").forEach(btn => {
      btn.onclick = function() {
        if (window.lastTemplate) {
          fetch(L.env.cgiBase + '/admin/network/wifi_ac/api/optimization?action=apply_template', {
            method: "POST",
            body: new URLSearchParams({macs: btn.dataset.mac, template: JSON.stringify(window.lastTemplate)})
          }).then(r => r.json()).then(res => {
            alert(_("模板重试结果: ") + JSON.stringify(res));
            showBatchProgress(res);
          });
        }
      };
    });
  }
}

// 升级队列拖拽排序与分阶段升级（支持拖拽调整顺序和分阶段升级）
function enableUpgradeQueueDrag() {
  let list = document.getElementById("upgrade-queue-list");
  if (!list) return;
  let dragging, dragIndex;
  list.querySelectorAll("li").forEach((li, idx) => {
    li.draggable = true;
    li.ondragstart = function() { dragging = li; dragIndex = idx; li.style.opacity = "0.5"; };
    li.ondragend = function() { li.style.opacity = ""; };
    li.ondragover = function(e) { e.preventDefault(); li.style.borderTop = "2px solid #409eff"; };
    li.ondragleave = function() { li.style.borderTop = ""; };
    li.ondrop = function(e) {
      e.preventDefault();
      li.style.borderTop = "";
      if (dragging && dragging !== li) {
        if (dragIndex < idx) li.after(dragging);
        else li.before(dragging);
        // 保存新顺序到后端
        let macs = Array.from(list.querySelectorAll("li")).map(x => x.dataset.mac).join(",");
        fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/upgrade_queue", {
          method: "POST",
          body: new URLSearchParams({macs})
        });
      }
    };
  });
  // 分阶段升级按钮
  let stageBtn = document.getElementById("upgrade-stage-btn");
  if (stageBtn) {
    stageBtn.onclick = function() {
      let stage = prompt(_("请输入每阶段升级设备数量"), "5");
      if (!stage) return;
      fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/upgrade_stage", {
        method: "POST",
        body: new URLSearchParams({stage})
      }).then(r => r.json()).then(res => {
        alert(res.msg || _("分阶段升级已启动"));
      });
    };
  }
}
