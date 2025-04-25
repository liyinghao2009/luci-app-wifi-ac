// 设置相关 JS
document.addEventListener("DOMContentLoaded", function() {
  function loadSettings() {
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/settings")
      .then(r => r.json())
      .then(data => {
        Object.keys(data).forEach(k => {
          let el = document.querySelector(`[name="${k}"]`);
          if (el) el.value = data[k];
        });
      });
  }
  loadSettings();

  const form = document.getElementById("settings-form");
  document.getElementById("save-settings").onclick = function() {
    const data = {};
    Array.from(form.elements).forEach(el => {
      if (el.name) data[el.name] = el.value;
    });
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/settings", {
      method: "POST",
      body: new URLSearchParams(data)
    }).then(r => r.json()).then(res => {
      document.getElementById("settings-msg").innerText = res.msg || "保存成功";
    });
  };

  document.getElementById("load-settings").onclick = function() {
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/settings")
      .then(r => r.json())
      .then(data => {
        Object.keys(data).forEach(k => {
          let el = document.querySelector(`[name="${k}"]`);
          if (el) el.value = data[k];
        });
        document.getElementById("settings-msg").innerText = _("配置已回读");
      });
  };

  document.getElementById("test-radius").onclick = function() {
    let server = document.querySelector("[name=radius_server]").value;
    let secret = document.querySelector("[name=radius_secret]").value;
    if (!server || !secret) {
      document.getElementById("settings-msg").innerText = _("请填写RADIUS服务器和密钥");
      return;
    }
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/settings", {
      method: "POST",
      body: new URLSearchParams({action: "test_radius", radius_server: server, radius_secret: secret})
    }).then(r => r.json()).then(res => {
      document.getElementById("settings-msg").innerText = res.msg || "";
    });
  };

  // 配置模板管理卡片视图逻辑
  document.getElementById("template-manage-btn").onclick = function() {
    document.getElementById("template-manage-view").style.display = "block";
    loadTemplateList();
  };
  function loadTemplateList() {
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/template_manage")
      .then(r => r.json())
      .then(res => {
        let list = res.templates || [];
        let html = "";
        list.forEach(tpl => {
          html += `<div class="template-card">
            <h4>${tpl.name || ""}</h4>
            <div class="tpl-vendor">${_("厂商")}: ${tpl.vendor || ""}</div>
            <pre>${tpl.config ? (typeof tpl.config === "string" ? tpl.config : JSON.stringify(tpl.config, null, 2)) : ""}</pre>
            <div class="tpl-actions">
              <button onclick="editTemplate('${tpl.name||""}','${tpl.vendor||""}',\`${tpl.config ? (typeof tpl.config === "string" ? tpl.config : JSON.stringify(tpl.config, null, 2)) : ""}\`)">${_("编辑")}</button>
              <button onclick="deleteTemplate('${tpl.name||""}')">${_("删除")}</button>
            </div>
          </div>`;
        });
        document.getElementById("template-list").innerHTML = html;
      });
  }
  document.getElementById("add-template-btn").onclick = function() {
    document.getElementById("add-template-form").style.display = "block";
    document.getElementById("tpl-name").value = "";
    document.getElementById("tpl-vendor").value = "";
    document.getElementById("tpl-config").value = "";
  };
  document.getElementById("tpl-cancel-btn").onclick = function() {
    document.getElementById("add-template-form").style.display = "none";
  };
  document.getElementById("tpl-save-btn").onclick = function() {
    let name = document.getElementById("tpl-name").value.trim();
    let vendor = document.getElementById("tpl-vendor").value.trim();
    let config = document.getElementById("tpl-config").value.trim();
    if (!name || !config) return alert(_("模板名称和配置必填"));
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/template_manage", {
      method: "POST",
      body: new URLSearchParams({name, vendor, config})
    }).then(r => r.json()).then(res => {
      alert(res.msg || "");
      if (res.code === 0) {
        document.getElementById("add-template-form").style.display = "none";
        loadTemplateList();
      }
    });
  };
  window.editTemplate = function(name, vendor, config) {
    document.getElementById("add-template-form").style.display = "block";
    document.getElementById("tpl-name").value = name;
    document.getElementById("tpl-vendor").value = vendor;
    document.getElementById("tpl-config").value = config;
  };
  window.deleteTemplate = function(name) {
    if (!confirm(_("确定删除模板?"))) return;
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/template_manage", {
      method: "DELETE",
      body: new URLSearchParams({name})
    }).then(r => r.json()).then(res => {
      alert(res.msg || "");
      loadTemplateList();
    });
  };

  document.getElementById("role-manage-btn").onclick = function() {
    window.location.href = L.env.cgiBase + "/admin/network/wifi_ac/settings#role-manage";
  };

  document.getElementById("factory-reset-btn").onclick = function() {
    if (!confirm(_("确定要恢复出厂设置并重启？"))) return;
    let pwd = prompt(_("请输入管理员密码确认"), "");
    if (!pwd) return;
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/factory_reset", {
      method: "POST",
      body: new URLSearchParams({password: pwd})
    }).then(r => r.json()).then(res => {
      document.getElementById("settings-msg").innerText = res.msg || "";
    });
  };

  document.getElementById("show-storage-btn").onclick = function() {
    fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/storage_info")
      .then(r => r.json())
      .then(res => {
        document.getElementById("log-storage-usage").innerText = (res.storage || "");
      });
  };
});
