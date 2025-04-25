function renderOverview() {
  fetch(L.env.cgiBase + "/admin/network/wifi_ac/api/overview")
    .then(r => r.json())
    .then(data => {
      // 统计
      document.getElementById("overview-stats").innerHTML =
        `设备总数: <b>${data.total}</b> 在线: <b style="color:#67c23a">${data.online}</b> 平均负载: <b>${data.avg_load}%</b>`;

      // 滚动通知
      let notify = document.getElementById("overview-notify");
      if (data.notifications && data.notifications.length) {
        let html = '<span style="margin-right:8px;">最近上线/离线:</span>';
        data.notifications.forEach(n => {
          html += `<span style="margin-right:12px;">
            <b>${n.mac}</b> <span style="color:${n.status==='online'?'#67c23a':'#e67c23'}">${n.status}</span>
            <span style="color:#888;">${n.time||''}</span>
            <button style="margin-left:2px;color:#aaa;background:none;border:none;cursor:pointer;" onclick="this.parentNode.style.display='none'">×</button>
          </span>`;
        });
        notify.innerHTML = html;
      } else {
        notify.innerHTML = "";
      }

      // 信号分布美化
      let sig = data.signal_dist || {};
      let sigChart = echarts.init(document.getElementById("overview-signal"));
      sigChart.setOption({
        title: {text: "信号分布", left: "center", textStyle: {fontSize: 15}},
        tooltip: {trigger: "item"},
        legend: {bottom: 0, left: "center"},
        series: [{
          name: "信号分布",
          type: "pie",
          radius: ["40%", "70%"],
          avoidLabelOverlap: false,
          label: {show: false},
          emphasis: {label: {show: true, fontSize: 16, fontWeight: "bold"}},
          data: [
            {value: sig.strong || 0, name: "强", itemStyle: {color: "#67c23a"}},
            {value: sig.medium || 0, name: "中", itemStyle: {color: "#e6a23c"}},
            {value: sig.weak || 0, name: "弱", itemStyle: {color: "#f56c6c"}}
          ],
          animation: true
        }]
      });

      // 仪表盘趋势图多指标切换
      let trend = data.trend || {};
      let chart = echarts.init(document.getElementById("overview-trend"));
      let metric = "load";
      let metricMap = {load: "平均负载", signal: "平均信号", clients: "接入数"};
      function setTrendOption(m) {
        chart.setOption({
          title: {text: metricMap[m], left: "center", textStyle: {fontSize: 15}},
          tooltip: {trigger: "axis"},
          xAxis: {type: "category", data: trend.time || []},
          yAxis: {type: "value"},
          series: [{
            type: "line",
            data: trend[m] || [],
            smooth: true,
            areaStyle: {color: m==="load"?"#409eff":(m==="signal"?"#e6a23c":"#67c23a"), opacity: 0.15},
            lineStyle: {width: 2, color: m==="load"?"#409eff":(m==="signal"?"#e6a23c":"#67c23a")},
            symbol: "circle",
            symbolSize: 7
          }]
        });
      }
      setTrendOption(metric);

      // 切换按钮
      let btns = "";
      Object.keys(metricMap).forEach(m => {
        btns += `<button style="margin-right:8px;padding:2px 12px;border-radius:3px;border:none;background:${metric===m?'#409eff':'#eee'};color:${metric===m?'#fff':'#333'};cursor:pointer;" onclick="window.setOverviewTrendMetric&&window.setOverviewTrendMetric('${m}')">${metricMap[m]}</button>`;
      });
      let trendDiv = document.getElementById("overview-trend");
      if (trendDiv) {
        let ctrl = document.getElementById("overview-trend-ctrl");
        if (!ctrl) {
          ctrl = document.createElement("div");
          ctrl.id = "overview-trend-ctrl";
          trendDiv.parentNode.insertBefore(ctrl, trendDiv);
        }
        ctrl.innerHTML = btns;
      }
      window.setOverviewTrendMetric = function(m) {
        metric = m;
        setTrendOption(m);
        // 按钮高亮
        let ctrl = document.getElementById("overview-trend-ctrl");
        if (ctrl) {
          Array.from(ctrl.querySelectorAll("button")).forEach(btn => {
            btn.style.background = btn.innerText === metricMap[m] ? "#409eff" : "#eee";
            btn.style.color = btn.innerText === metricMap[m] ? "#fff" : "#333";
          });
        }
      };
    });
}

document.addEventListener("DOMContentLoaded", renderOverview);

console.log("WiFi AC 前端入口加载完成");
