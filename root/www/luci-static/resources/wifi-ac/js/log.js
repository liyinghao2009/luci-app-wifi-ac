// 日志相关 JS
document.addEventListener("DOMContentLoaded", function() {
  // 获取token和user（如有权限控制需求可补充）
  function getToken() {
    return (window.L && L.env && L.env.token) ? L.env.token : "";
  }
  function getUser() {
    return (window.L && L.env && L.env.user) ? L.env.user : "";
  }

  function fetchLogs(params, cb) {
    let url = L.env.cgiBase + "/admin/network/wifi_ac/api/log";
    params = params || {};
    params.token = getToken();
    params.user = getUser();
    url += "?" + Object.keys(params).map(k => k + "=" + encodeURIComponent(params[k])).join("&");
    fetch(url).then(r => r.json()).then(cb);
  }
  function renderLogs(logs) {
    const tbody = document.querySelector("#log-table tbody");
    tbody.innerHTML = "";
    (logs || []).forEach(e => {
      let tr = document.createElement("tr");
      tr.innerHTML = `<td>${new Date((e.timestamp || 0) * 1000).toLocaleString()}</td><td>${e.type}</td><td>${e.vendor||""}</td><td>${e.user||""}</td><td>${e.msg||""}</td><td>${e.detail||""}</td>`;
      tbody.appendChild(tr);
    });
  }
  function doSearch() {
    let params = {
      keyword: document.getElementById("log-keyword").value,
      type: document.getElementById("log-type").value,
      vendor: document.getElementById("log-vendor").value,
      user: document.getElementById("log-user").value,
      since: document.getElementById("log-since").value ? (new Date(document.getElementById("log-since").value).getTime()/1000|0) : "",
      until: document.getElementById("log-until").value ? (new Date(document.getElementById("log-until").value).getTime()/1000|0) : ""
    };
    fetchLogs(params, data => renderLogs(data.logs));
  }
  document.getElementById("log-search").onclick = doSearch;
  document.getElementById("log-type").onchange = doSearch;
  document.getElementById("log-keyword").oninput = function(e) { if (e.target.value.length === 0) doSearch(); };
  document.getElementById("log-vendor").oninput = function(e) { if (e.target.value.length === 0) doSearch(); };
  document.getElementById("log-user").oninput = function(e) { if (e.target.value.length === 0) doSearch(); };
  document.getElementById("log-since").onchange = doSearch;
  document.getElementById("log-until").onchange = doSearch;

  document.getElementById("log-export-csv").onclick = function() {
    let params = {
      keyword: document.getElementById("log-keyword").value,
      type: document.getElementById("log-type").value,
      vendor: document.getElementById("log-vendor").value,
      user: document.getElementById("log-user").value,
      since: document.getElementById("log-since").value ? (new Date(document.getElementById("log-since").value).getTime()/1000|0) : "",
      until: document.getElementById("log-until").value ? (new Date(document.getElementById("log-until").value).getTime()/1000|0) : "",
      export: "csv",
      token: getToken(),
      user: getUser()
    };
    window.open(L.env.cgiBase + "/admin/network/wifi_ac/api/log?" + Object.keys(params).map(k => k + "=" + encodeURIComponent(params[k])).join("&"));
  };

  // 日志导出PDF美化（需引入pdfmake库）
  document.getElementById("log-export-pdf").onclick = function() {
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/log?export=pdf")
      .then(r => r.text())
      .then(pdfText => {
        // 使用 pdfmake 生成美观PDF（简单示例）
        if (window.pdfMake) {
          var docDefinition = {
            content: [
              { text: 'WiFi-AC 日志导出', style: 'header' },
              { text: new Date().toLocaleString(), style: 'subheader' },
              { text: pdfText, style: 'logtext', fontSize: 10 }
            ],
            styles: {
              header: { fontSize: 18, bold: true, margin: [0,0,0,10] },
              subheader: { fontSize: 12, margin: [0,0,0,10] },
              logtext: { fontSize: 10 }
            }
          };
          pdfMake.createPdf(docDefinition).download("wifi-ac-log.pdf");
        } else {
          // fallback: 直接下载后端生成的PDF文本
          let blob = new Blob([pdfText], {type: "application/pdf"});
          let a = document.createElement("a");
          a.href = URL.createObjectURL(blob);
          a.download = "wifi-ac-log.pdf";
          a.click();
        }
      });
  };

  doSearch();

  // WebSocket实时告警推送
  if ("WebSocket" in window) {
    try {
      let ws = new WebSocket("ws://" + location.host + "/ws/wifi-ac/alarm");
      ws.onmessage = function(evt) {
        let data = JSON.parse(evt.data);
        document.getElementById("log-alarm").innerText = "<%:告警%>: " + (data.msg || "");
      };
    } catch (e) {}
  }

  // 日志存储占用展示
  function showLogStorageUsage() {
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/storage_info")
      .then(r => r.json())
      .then(res => {
        document.getElementById("log-storage-usage").innerText = "日志空间占用: " + (res.storage || "");
      });
  }
  showLogStorageUsage();

  // 日志API权限细粒度控制（前端按钮显示/隐藏）
  function checkLogPermission() {
    // 假设 window.L.env.permissions 为权限数组
    let perms = window.L && window.L.env && window.L.env.permissions;
    if (perms && !perms.includes("log_export")) {
      document.getElementById("log-export-csv").style.display = "none";
      document.getElementById("log-export-pdf").style.display = "none";
    }
    if (perms && !perms.includes("log_query")) {
      document.getElementById("log-search").style.display = "none";
    }
  }
  checkLogPermission();

  // 日志存储占用展示
  fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/storage_info")
    .then(r => r.json())
    .then(res => {
      if (res && res.storage) {
        document.getElementById("log-storage-usage").innerText = "<%:日志占用%>: " + res.storage;
      }
    });
});
