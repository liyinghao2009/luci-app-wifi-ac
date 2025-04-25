// 固件升级相关 JS

document.addEventListener("DOMContentLoaded", function() {
  let firmwareList = [];
  let upgradeQueue = [];

  function fetchFirmwareList(filters) {
    let url = L.env.cgiBase + "/admin/network/wifi_ac/api/firmware";
    if (filters) {
      let params = [];
      if (filters.vendor) params.push("vendor=" + encodeURIComponent(filters.vendor));
      if (filters.model) params.push("model=" + encodeURIComponent(filters.model));
      if (filters.version) params.push("version=" + encodeURIComponent(filters.version));
      if (params.length) url += "?" + params.join("&");
    }
    fetch(url)
      .then(r => r.json())
      .then(data => {
        firmwareList = data.firmwares || [];
        renderFirmwareTable();
        renderFirmwareSelect();
      });
  }

  function renderFirmwareTable() {
    const tbody = document.querySelector("#firmware-table tbody");
    tbody.innerHTML = "";
    firmwareList.forEach(fw => {
      let tr = document.createElement("tr");
      tr.innerHTML = `<td>${fw.name}</td><td>${fw.vendor}</td><td>${fw.model}</td><td>${fw.version}</td><td>${fw.md5}</td><td>${fw.size}</td>`;
      tbody.appendChild(tr);
    });
  }

  function renderFirmwareSelect() {
    let sel = document.getElementById("upgrade-firmware-select");
    if (!sel) return;
    sel.innerHTML = '<option value="">请选择固件</option>' + firmwareList.map(fw =>
      `<option value="${fw.name}">${fw.vendor || ""} ${fw.model || ""} ${fw.version || ""}</option>`
    ).join("");
  }

  document.getElementById("firmware-filter-btn").onclick = function() {
    fetchFirmwareList({
      vendor: document.getElementById("firmware-filter-vendor").value.trim(),
      model: document.getElementById("firmware-filter-model").value.trim(),
      version: document.getElementById("firmware-filter-version").value.trim()
    });
  };
  document.getElementById("firmware-clear-btn").onclick = function() {
    document.getElementById("firmware-filter-vendor").value = "";
    document.getElementById("firmware-filter-model").value = "";
    document.getElementById("firmware-filter-version").value = "";
    fetchFirmwareList();
  };

  document.getElementById("upload-btn").onclick = function() {
    let fileInput = document.getElementById("firmware-upload");
    let vendor = document.getElementById("firmware-vendor").value.trim();
    let model = document.getElementById("firmware-model").value.trim();
    let version = document.getElementById("firmware-version").value.trim();
    let file = fileInput.files[0];
    if (!file || !vendor || !model || !version) return alert("请填写完整信息并选择文件");
    let formData = new FormData();
    formData.append("file", file);
    formData.append("vendor", vendor);
    formData.append("model", model);
    formData.append("version", version);
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/firmware", {
      method: "POST",
      body: formData
    }).then(r => r.json()).then(res => {
      alert(res.msg);
      fetchFirmwareList();
    });
  };

  // 升级队列管理
  function fetchUpgradeQueue() {
    // 假设后端返回升级队列（可扩展为API获取）
    // 这里用前端模拟，实际应从后端拉取
    upgradeQueue = [];
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/device_list")
      .then(r => r.json())
      .then(data => {
        (data.devices || []).forEach(dev => {
          upgradeQueue.push({mac: dev.mac, vendor: dev.vendor, model: dev.model, status: dev.status});
        });
        renderUpgradeQueue();
      });
  }

  function renderUpgradeQueue() {
    let ul = document.getElementById("upgrade-queue-list");
    ul.innerHTML = "";
    upgradeQueue.forEach(item => {
      let li = document.createElement("li");
      li.dataset.mac = item.mac;
      li.innerHTML = `<b>${item.mac}</b> <span style="margin-left:8px;">${item.vendor || ""} ${item.model || ""}</span> <span style="margin-left:8px;color:${item.status=='online'?'#67c23a':'#888'}">${item.status||''}</span>`;
      ul.appendChild(li);
    });
    enableUpgradeQueueDrag();
  }

  document.getElementById("upgrade-refresh-btn").onclick = fetchUpgradeQueue;

  // 拖拽排序
  window.enableUpgradeQueueDrag = function() {
    let list = document.getElementById("upgrade-queue-list");
    if (!list) return;
    let dragging, dragIndex;
    Array.from(list.children).forEach((li, idx) => {
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
          let macs = Array.from(list.querySelectorAll("li")).map(x => x.dataset.mac);
          fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/firmware/queue/update", {
            method: "POST",
            body: JSON.stringify(macs)
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

  // 分阶段升级
  document.getElementById("upgrade-stage-btn").onclick = function() {
    let stage = prompt("请输入每阶段升级设备数量", "5");
    if (!stage) return;
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/upgrade_stage", {
      method: "POST",
      body: new URLSearchParams({stage})
    }).then(r => r.json()).then(res => {
      alert(res.msg || "分阶段升级已启动");
    });
  };

  // 开始升级
  document.getElementById("start-upgrade-btn").onclick = function() {
    let firmware = document.getElementById("upgrade-firmware-select").value;
    let aps = Array.from(document.querySelectorAll("#upgrade-queue-list li")).map(li => li.dataset.mac).join(",");
    if (!firmware || !aps) return alert("请选择固件和设备");
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/firmware", {
      method: "PUT",
      headers: {"Content-Type":"application/x-www-form-urlencoded"},
      body: "firmware=" + encodeURIComponent(firmware) + "&aps[]=" + encodeURIComponent(aps)
    }).then(r => r.json()).then(res => {
      alert(res.msg);
      updateUpgradeProgress();
    });
  };

  function updateUpgradeProgress() {
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/firmware?status=1")
      .then(r => r.json())
      .then(data => {
        let div = document.getElementById("upgrade-progress");
        let bar = document.getElementById("upgrade-progress-bar-inner");
        let total = Object.keys(data).length;
        let done = Object.values(data).filter(v => v === "upgrading" || v === "success").length;
        let percent = total ? Math.round((done / total) * 100) : 0;
        bar.style.width = percent + "%";
        div.innerHTML = "";
        Object.keys(data).forEach(mac => {
          div.innerHTML += `<div>${mac}: ${data[mac]}</div>`;
        });
      });
  }
  setInterval(updateUpgradeProgress, 3000);

  // 初始化
  fetchFirmwareList();
  fetchUpgradeQueue();
});

// 日志存储占用展示、导出PDF美化、API权限细粒度控制建议：
// 1. 日志存储占用展示：在日志页面调用 /admin/network/wifi_ac/api/storage_info，显示 storage 字段。
// 2. 日志导出PDF美化：前端可用如 jsPDF、pdfmake 等库生成更美观PDF，后端可返回结构化数据。
// 3. 日志API权限细粒度控制：前端根据 window.L.env.permissions 控制导出/查询按钮显示，后端已支持权限校验。
