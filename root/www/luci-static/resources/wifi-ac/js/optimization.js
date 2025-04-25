// 优化相关 JS
document.addEventListener("DOMContentLoaded", function() {
  const progress = document.getElementById("opt-progress");
  const progressText = document.getElementById("opt-progress-text");
  const logBox = document.getElementById("opt-log");

  function updateProgress() {
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/optimization?action=progress")
      .then(r => r.json())
      .then(data => {
        progress.value = data.progress || 0;
        progressText.innerText = (data.progress || 0) + "%";
        logBox.innerText = (data.log || []).join("\n");
      });
  }

  // 获取token（可从cookie或全局变量获取）
  function getToken() {
    // 示例：假设token存储在window.L.env.token或cookie
    return (window.L && L.env && L.env.token) || (document.cookie.match(/token=([^;]+)/)||[])[1] || "";
  }

  // fetch请求增加token参数（以POST为例）
  function postWithToken(url, params) {
    params = params || {};
    params.token = getToken();
    return fetch(url, {
      method: "POST",
      body: new URLSearchParams(params)
    });
  }

  // 例如：一键自动优化
  document.getElementById("auto-opt-btn").onclick = function() {
    postWithToken(L.env.cgiBase + "/admin/network/wifi_ac/api/optimization?action=auto")
      .then(r => r.json())
      .then(() => {
        updateProgress();
      });
  };

  // 手动信道/功率分配
  document.getElementById("manual-opt-btn").onclick = function() {
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/device_list")
      .then(r => r.json())
      .then(data => {
        let aps = data.devices || [];
        let apSel = document.createElement("select");
        apSel.id = "ap-select";
        aps.forEach(ap => {
          let opt = document.createElement("option");
          opt.value = ap.mac;
          opt.innerText = ap.mac + (ap.model ? " (" + ap.model + ")" : "");
          apSel.appendChild(opt);
        });
        let chSel = document.createElement("select");
        chSel.id = "channel-select";
        ["1","6","11","36","40","149"].forEach(ch => {
          let opt = document.createElement("option");
          opt.value = ch;
          opt.innerText = ch;
          chSel.appendChild(opt);
        });
        let txInput = document.createElement("input");
        txInput.type = "number";
        txInput.placeholder = "功率";
        let btn = document.createElement("button");
        btn.innerText = "下发";
        btn.onclick = function() {
          let mac = apSel.value;
          let channel = chSel.value;
          let txpower = txInput.value;
          fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/optimization?action=manual", {
            method: "POST",
            headers: {"Content-Type":"application/x-www-form-urlencoded"},
            body: "mac=" + encodeURIComponent(mac) + "&channel=" + encodeURIComponent(channel) + "&txpower=" + encodeURIComponent(txpower)
          })
          .then(r => r.json())
          .then(res => alert(res.msg || "已下发"));
        };
        let wrap = document.createElement("div");
        wrap.style.margin = "10px 0";
        wrap.appendChild(document.createTextNode("手动分配信道/功率："));
        wrap.appendChild(apSel);
        wrap.appendChild(chSel);
        wrap.appendChild(txInput);
        wrap.appendChild(btn);
        document.body.appendChild(wrap);
        setTimeout(() => wrap.remove(), 20000);
      });
  };

  // 批量应用模板
  document.getElementById("apply-template-btn").onclick = function() {
    let tplName = document.getElementById("template-select").value;
    if (!tplName) return alert("请选择模板");
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/templates")
      .then(r => r.json())
      .then(res => {
        let tpls = res.templates || [];
        let tpl = tpls.find(t=>t.name===tplName);
        if (!tpl) return alert("模板不存在");
        let macs = prompt("请输入批量应用模板的AP MAC（逗号分隔）");
        if (!macs) return;
        fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/optimization?action=apply_template", {
          method: "POST",
          body: new URLSearchParams({macs, template: JSON.stringify(tpl)})
        }).then(r => r.json()).then(res => {
          alert(res.msg || "模板批量应用已下发");
          updateProgress();
        });
      });
  };

  // 负载均衡阈值设置
  let setThresholdBtn = document.createElement("button");
  setThresholdBtn.innerText = "设置负载均衡阈值";
  setThresholdBtn.onclick = function() {
    let max_clients = prompt("请输入每AP最大接入数", "32");
    let strategy = prompt("请输入负载均衡策略(balance/priority)", "balance");
    postWithToken(L.env.cgiBase + "/admin/network/wifi_ac/api/optimization_threshold", {max_clients, strategy})
      .then(r => r.json()).then(res => alert(res.msg));
  };
  document.querySelector("div").appendChild(setThresholdBtn);

  // 定时刷新进度与日志
  setInterval(updateProgress, 2000);
  updateProgress();

  // 热力图动态数据（后端采集信道热力图）
  function updateHeatmap() {
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/channel_heatmap")
      .then(r => r.json())
      .then(res => {
        let data = res.data || [];
        let chart = echarts.init(document.getElementById('heatmap'));
        chart.setOption({
          tooltip: {},
          xAxis: {type: 'category', data: ["1", "6", "11", "36", "40", "149"]},
          yAxis: {type: 'category', data: ["2.4G", "5G"]},
          visualMap: {min: -100, max: 0, calculable: true, orient: 'horizontal', left: 'center', bottom: '15%'},
          series: [{
            type: 'heatmap',
            data: data,
            label: {show: true},
            emphasis: {itemStyle: {shadowBlur: 10, shadowColor: 'rgba(0,0,0,0.5)'}}
          }]
        });
      });
  }
  updateHeatmap();

  // 手动信道分配下拉框
  function renderManualChannelSelect() {
    // 获取AP列表
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/device_list")
      .then(r => r.json())
      .then(data => {
        let aps = data.devices || [];
        let apSel = document.createElement("select");
        apSel.id = "ap-select";
        aps.forEach(ap => {
          let opt = document.createElement("option");
          opt.value = ap.mac;
          opt.innerText = ap.mac + (ap.model ? " (" + ap.model + ")" : "");
          apSel.appendChild(opt);
        });
        let chSel = document.createElement("select");
        chSel.id = "channel-select";
        ["1","6","11","36","40","149"].forEach(ch => {
          let opt = document.createElement("option");
          opt.value = ch;
          opt.innerText = ch;
          chSel.appendChild(opt);
        });
        let btn = document.createElement("button");
        btn.innerText = "下发信道";
        btn.onclick = function() {
          let mac = apSel.value;
          let channel = chSel.value;
          fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/set_channel", {
            method: "POST",
            headers: {"Content-Type":"application/x-www-form-urlencoded"},
            body: "mac=" + encodeURIComponent(mac) + "&channel=" + encodeURIComponent(channel)
          })
          .then(r => r.json())
          .then(res => alert(res.msg || "已下发"));
        };
        let wrap = document.createElement("div");
        wrap.style.margin = "10px 0";
        wrap.appendChild(document.createTextNode("手动分配信道："));
        wrap.appendChild(apSel);
        wrap.appendChild(chSel);
        wrap.appendChild(btn);
        let heatmapDiv = document.getElementById("heatmap");
        if (heatmapDiv) heatmapDiv.parentNode.insertBefore(wrap, heatmapDiv.nextSibling);
      });
  }
  renderManualChannelSelect();

  // 动态获取并渲染趋势对比图
  function updateTrendChart() {
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/optimization_trend")
      .then(r => r.json())
      .then(data => {
        var ctx = document.getElementById('trend-chart').getContext('2d');
        if (window._optTrendChart) window._optTrendChart.destroy();
        window._optTrendChart = new Chart(ctx, {
          type: 'line',
          data: {
            labels: data.time || [],
            datasets: [
              { label: 'AP1负载', data: data.ap1 || [], borderColor: 'red', fill: false },
              { label: 'AP2负载', data: data.ap2 || [], borderColor: 'blue', fill: false }
            ]
          }
        });
      });
  }
  setInterval(updateTrendChart, 60000);
  updateTrendChart();

  // Chart.js趋势图
  var ctx = document.getElementById('trend-chart').getContext('2d');
  new Chart(ctx, {
    type: 'line',
    data: {
      labels: ['10:00','10:05','10:10'],
      datasets: [
        { label: 'AP1负载', data: [20,40,30], borderColor: 'red', fill: false },
        { label: 'AP2负载', data: [30,35,32], borderColor: 'blue', fill: false }
      ]
    }
  });

  // 初始化WebSocket监听优化进度
  const acIp = location.host;
  const ws = new WebSocket(`ws://${acIp}/ws/wifi-ac/optimization`);
  ws.onmessage = (event) => {
    const data = JSON.parse(event.data);
    updateProgressBar(data.progress);
    appendLog(data.message);
  };

  function updateProgressBar(progress) {
    document.getElementById("opt-progress-bar").innerText = "进度: " + progress + "%";
  }
  function appendLog(msg) {
    const logDiv = document.getElementById("opt-log");
    logDiv.innerText += msg + "\n";
  }

  // 模板下拉框渲染（示例，实际应AJAX获取模板列表）
  fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/templates")
    .then(r => r.json())
    .then(res => {
      let sel = document.getElementById("template-select");
      sel.innerHTML = '<option value="">请选择模板</option>';
      (res.templates || []).forEach(tpl => {
        let opt = document.createElement("option");
        opt.value = tpl.name;
        opt.innerText = tpl.name;
        sel.appendChild(opt);
      });
    });

  // 功率调节控件适配（原生和三方AP）
  window.renderTxPowerInput = function(vendor, model, mac, current) {
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/txpower_range?vendor=" + encodeURIComponent(vendor) + "&model=" + encodeURIComponent(model))
      .then(r => r.json())
      .then(range => {
        let box = document.getElementById("txpower-box-" + mac);
        if (!box) return;
        box.innerHTML = "";
        let input;
        if (vendor.toLowerCase() === "openwrt") {
          input = document.createElement("input");
          input.type = "range";
          input.min = range.min;
          input.max = range.max;
          input.step = range.step;
          input.value = current || range.max;
        } else {
          input = document.createElement("input");
          input.type = "number";
          input.min = range.min;
          input.max = range.max;
          input.step = range.step;
          input.value = current || range.max;
          // 三方AP可扩展自定义控件
        }
        input.onchange = function() {
          fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/set_power/" + encodeURIComponent(mac) + "/" + encodeURIComponent(vendor), {
            method: "POST",
            body: input.value
          }).then(r => r.json()).then(res => {
            if(res.status !== "success") alert(res.message || "设置失败");
            document.getElementById("power-val-" + mac).innerText = input.value;
          });
        };
        box.appendChild(input);
      });
  };

  // 趋势图定时刷新
  function updateTrendChart() {
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/trend_data")
      .then(r => r.json())
      .then(data => {
        let chart = echarts.init(document.getElementById("trend-chart"));
        chart.setOption({
          xAxis: {type: 'category', data: data.time},
          yAxis: [{type: 'value', name: '负载'}, {type: 'value', name: '信号'}],
          series: [
            {type: 'line', data: data.avg_load, name: '平均负载', yAxisIndex: 0},
            {type: 'line', data: data.avg_signal, name: '平均信号', yAxisIndex: 1}
          ]
        });
      });
  }
  setInterval(updateTrendChart, 60000);
  updateTrendChart();

  // 功率调节控件细粒度适配（与device.js一致，便于复用）
  window.renderTxPowerInput = function(vendor, model, mac, current) {
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/txpower_range?vendor=" + encodeURIComponent(vendor) + "&model=" + encodeURIComponent(model))
      .then(r => r.json())
      .then(range => {
        let box = document.getElementById("txpower-box-" + mac);
        if (!box) return;
        box.innerHTML = "";
        let input;
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
          input = document.createElement("input");
          input.type = "number";
          input.value = current || "";
        }
        input.onchange = function() {
          fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/set_power/" + encodeURIComponent(mac) + "/" + encodeURIComponent(vendor) + "?model=" + encodeURIComponent(model), {
            method: "POST",
            body: input.value
          }).then(r => r.json()).then(res => {
            if(res.status !== "success") alert(res.message || "设置失败");
            document.getElementById("power-val-" + mac).innerText = input.value;
          });
        };
        box.appendChild(input);
      });
  };

  // 趋势图自定义时间范围与导出（联动后端API）
  window.updateTrendChart = function(start, end, metric) {
    // start/end: yyyy-MM-ddTHH:mm
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/trend_data", {
      method: "POST",
      body: new URLSearchParams({start_time: start, end_time: end, metric: metric})
    })
      .then(r => r.json())
      .then(data => {
        let chart = echarts.init(document.getElementById("trend-chart"));
        chart.setOption({
          xAxis: {type: 'category', data: data.time},
          yAxis: {type: 'value', name: metric === "signal" ? "信号" : (metric === "clients" ? "接入数" : "负载")},
          series: [
            {type: 'line', data: data.data, name: metric === "signal" ? "平均信号" : (metric === "clients" ? "接入数" : "平均负载")}
          ]
        });
      });
  };
  window.exportTrendChart = function() {
    // 导出当前趋势图为CSV
    let start = document.getElementById("trend-start").value;
    let end = document.getElementById("trend-end").value;
    let metric = document.getElementById("trend-metric").value;
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/trend_data", {
      method: "POST",
      body: new URLSearchParams({start_time: start, end_time: end, metric: metric})
    })
      .then(r => r.json())
      .then(data => {
        let csv = "时间," + (metric === "signal" ? "平均信号" : (metric === "clients" ? "接入数" : "平均负载")) + "\n";
        for (let i = 0; i < (data.time || []).length; i++) {
          csv += (data.time[i] || "") + "," + (data.data[i] || "") + "\n";
        }
        let a = document.createElement("a");
        a.href = URL.createObjectURL(new Blob([csv], {type: "text/csv"}));
        a.download = "trend.csv";
        a.click();
      });
  };

  // 优化操作权限细粒度校验
  function hasPermission(action) {
    return !window.L.env.permissions || window.L.env.permissions.includes(action);
  }

  // 批量操作/模板应用失败详细展示与重试（与device.js一致）
  window.showBatchProgress = function(summary) {
    let el = document.getElementById("batch-progress") || document.getElementById("opt-log");
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
    if (summary.fail > 0 && summary.detail) {
      el.innerHTML += "<br>" + _("失败设备:") + "<ul>" +
        Object.keys(summary.detail).map(mac => {
          let info = summary.detail[mac];
          let msg = typeof info === "object" ? (info.msg || info.error || JSON.stringify(info)) : info;
          return `<li>${mac}: ${msg} <button class="retry-btn" data-mac="${mac}">${_("重试")}</button></li>`;
        }).join("") + "</ul>";
      el.querySelectorAll(".retry-btn").forEach(btn => {
        btn.onclick = function() {
          fetch(L.env.cgiBase + '/admin/network/wifi_ac/api/device_batch', {
            method: "POST",
            body: new URLSearchParams({action: summary.action || "reboot", macs: btn.dataset.mac})
          }).then(r => r.json()).then(res => {
            alert(_("重试结果: ") + JSON.stringify(res));
            window.showBatchProgress(res);
          });
        };
      });
    }
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
              window.showBatchProgress(res);
            });
          }
        };
      });
    }
  };

  // 升级队列拖拽排序与分阶段升级（如有相关UI，可参考device.js的enableUpgradeQueueDrag实现）
  window.enableUpgradeQueueDrag = function() {
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
        let stage = prompt("请输入每阶段升级设备数量", "5");
        if (!stage) return;
        fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/upgrade_stage", {
          method: "POST",
          body: new URLSearchParams({stage})
        }).then(r => r.json()).then(res => {
          alert(res.msg || "分阶段升级已启动");
        });
      };
    }
  };

});
