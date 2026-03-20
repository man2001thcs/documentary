Để triển khai **Grafana + Prometheus + Loki** trên **Kubernetes (k8s)**, bạn có thể sử dụng **Helm** – công cụ quản lý chart phổ biến nhất cho k8s. Dưới đây là hướng dẫn triển khai chuẩn, gọn gàng và dễ quản lý:

---

## 🔧 **1. Chuẩn bị**

* Đã cài Helm v3+
* Đã có Kubernetes cluster đang hoạt động (Minikube, K3s, EKS, GKE, etc.)
* Có `kubectl` đang kết nối đúng cluster

---

## 📦 **2. Cài đặt Prometheus**

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/prometheus \
  -f prometheus-values.yaml \
  --namespace monitoring-stuff --create-namespace

helm install prometheus prometheus-community/prometheus --version 14.8.0 --namespace monitoring-stuff --create-namespace

```



> 🧠 Bạn có thể thêm cấu hình trong file `values.yaml` nếu muốn tùy chỉnh scrape targets.

---

## 📦 **3. Cài đặt Grafana**

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install grafana grafana/grafana \
  -f grafana-values.yaml \
  --namespace monitoring-stuff
```

🔑 **Lấy password admin Grafana:**

```bash
kubectl get secret --namespace monitoring-stuff grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

🌐 **Truy cập UI Grafana:**

```bash
kubectl port-forward svc/grafana 3000:80 -n monitoring-stuff
# rồi mở http://localhost:3000
```

---

## 📦 **4. Cài đặt Loki + Promtail (Log collector)**

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install loki grafana/loki-stack \
  --namespace monitoring-stuff \
  --set promtail.enabled=true
```

> Bạn có thể tắt Prometheus nếu đã cài ở bước 2:

```bash
--set prometheus.enabled=false
```

---

## 📊 **5. Cấu hình Datasources trong Grafana**

Sau khi đã vào UI Grafana:

1. Vào **Configuration → Data Sources**
2. Add:

   * **Prometheus**:

     * URL: `http://prometheus-server.monitoring-stuff.svc.cluster.local`
   * **Loki**:

     * URL: `http://loki.monitoring-stuff.svc.cluster.local:3100`

---

## ✅ **6. Kiểm tra Logs + Metrics**

* **Explore → Chọn datasource Loki → Chọn label `{job="kubernetes"}`** để xem logs
* Tạo dashboard Prometheus để xem metrics như CPU, memory, HTTP requests, v.v.

---

## 📁 Tuỳ chỉnh cấu hình (values.yaml - tùy chọn)

Bạn có thể xuất cấu hình Helm mặc định để tuỳ chỉnh:

```bash
helm show values grafana/grafana > grafana-values.yaml
helm show values prometheus-community/prometheus > prometheus-values.yaml
helm show values grafana/loki-stack > loki-values.yaml
```

Sau đó cài lại bằng lệnh:

```bash
helm upgrade --install grafana grafana/grafana -f grafana-values.yaml -n monitoring-stuff
```

---

## 🧩 Gợi ý: Cài thêm node-exporter để thu thập metric từ node

```bash
helm install node-exporter prometheus-community/prometheus-node-exporter -n monitoring-stuff
```

---

## 📚 Tổng kết

| Component  | Helm Chart                        | Namespace  | Port | Purpose          |
| ---------- | --------------------------------- | ---------- | ---- | ---------------- |
| Prometheus | `prometheus-community/prometheus` | monitoring-stuff | 9090 | Thu thập metrics |
| Grafana    | `grafana/grafana`                 | monitoring-stuff | 3000 | Dashboard UI     |
| Loki       | `grafana/loki-stack`              | monitoring-stuff | 3100 | Thu thập logs    |
| Promtail   | Tích hợp trong Loki chart         | monitoring-stuff | n/a  | Agent gửi logs   |

---

Nếu bạn cần file `values.yaml` mẫu cho từng chart (tối ưu cho prod/dev), cứ yêu cầu mình nhé.
