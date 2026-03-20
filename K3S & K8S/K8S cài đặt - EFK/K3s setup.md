# Hướng Dẫn Cài EFK lên K8S Cluster

## Giới thiệu

Khi chạy nhiều dịch vụ và ứng dụng trên một cụm Kubernetes, một hệ thống logging tập trung ở cấp cụm có thể giúp bạn nhanh chóng sàng lọc và phân tích lượng dữ liệu log lớn do các Pods tạo ra. Một giải pháp logging tập trung phổ biến là Elasticsearch, Fluentd, và Kibana (EFK) stack.

Elasticsearch là một công cụ tìm kiếm thời gian thực, phân tán và có khả năng mở rộng, cho phép tìm kiếm toàn văn và có cấu trúc, cũng như phân tích. Nó thường được sử dụng để lập chỉ mục và tìm kiếm qua các lượng dữ liệu log lớn, nhưng cũng có thể được sử dụng để tìm kiếm nhiều loại tài liệu khác nhau.

Elasticsearch thường được triển khai cùng với Kibana, một frontend trực quan hóa dữ liệu mạnh mẽ và bảng điều khiển cho Elasticsearch. Kibana cho phép bạn khám phá dữ liệu log Elasticsearch qua giao diện web và xây dựng các bảng điều khiển và truy vấn để nhanh chóng trả lời các câu hỏi và có được cái nhìn sâu sắc vào các ứng dụng Kubernetes của bạn.

Trong hướng dẫn này, chúng ta sẽ sử dụng Fluentd để thu thập, chuyển đổi và gửi dữ liệu log đến backend Elasticsearch. Fluentd là một bộ thu thập dữ liệu mã nguồn mở phổ biến mà chúng ta sẽ cài đặt trên các node Kubernetes để theo dõi các file log của container, lọc và chuyển đổi dữ liệu log, và chuyển nó đến cụm Elasticsearch, nơi nó sẽ được lập chỉ mục và lưu trữ.

Chúng ta sẽ bắt đầu bằng cách cấu hình và khởi chạy một cụm Elasticsearch có khả năng mở rộng, và sau đó tạo Dịch vụ và Deployment cho Kibana trên Kubernetes. Cuối cùng, chúng ta sẽ cài đặt Fluentd như một DaemonSet để nó chạy trên mọi node worker của Kubernetes.

Nếu bạn đang tìm kiếm một dịch vụ lưu trữ Kubernetes được quản lý, hãy xem xét dịch vụ Kubernetes đơn giản, được quản lý của chúng tôi được xây dựng để phát triển.

### Điều kiện tiên quyết

Trước khi bắt đầu với hướng dẫn này, hãy đảm bảo bạn có các thành phần sau:

- Một cụm Kubernetes phiên bản 1.10+ với kiểm soát truy cập dựa trên vai trò (RBAC) được kích hoạt.
- Đảm bảo cụm của bạn có đủ tài nguyên để triển khai EFK stack, nếu không hãy mở rộng cụm bằng cách thêm các node worker. Chúng ta sẽ triển khai một cụm Elasticsearch 3 Pod (bạn có thể giảm xuống 1 nếu cần thiết), cũng như một Pod Kibana duy nhất. Mỗi node worker cũng sẽ chạy một Pod Fluentd. Cụm trong hướng dẫn này bao gồm 3 node worker và một control plane được quản lý.
- Công cụ dòng lệnh kubectl được cài đặt trên máy tính của bạn, được cấu hình để kết nối với cụm của bạn. Bạn có thể đọc thêm về việc cài đặt kubectl trong tài liệu chính thức.

Khi bạn đã có các thành phần này, bạn đã sẵn sàng bắt đầu với hướng dẫn này.

## Chi tiết cài đặt

### Bước 1 — Tạo Namespace

Trước khi triển khai cụm Elasticsearch, chúng ta sẽ tạo một Namespace để cài đặt tất cả các công cụ logging của chúng ta. Kubernetes cho phép bạn tách các đối tượng chạy trong cụm của bạn bằng cách sử dụng một khái niệm "cụm ảo" gọi là Namespaces. Trong hướng dẫn này, chúng ta sẽ tạo một namespace `kube-logging` để cài đặt các thành phần của EFK stack. Namespace này cũng cho phép chúng ta nhanh chóng dọn dẹp và xóa bỏ stack logging mà không ảnh hưởng đến cụm Kubernetes.

Đầu tiên, kiểm tra các Namespace hiện có trong cụm của bạn bằng cách sử dụng kubectl:

```sh
kubectl get namespaces
```

Bạn sẽ thấy ba Namespace ban đầu sau, được cài đặt sẵn với cụm Kubernetes của bạn:

```
NAME          STATUS    AGE
default       Active    5m
kube-system   Active    5m
kube-public   Active    5m
```

Namespace `default` chứa các đối tượng được tạo ra mà không chỉ định Namespace. Namespace `kube-system` chứa các đối tượng được tạo và sử dụng bởi hệ thống Kubernetes, như kube-dns, kube-proxy, và kubernetes-dashboard. Bạn nên giữ Namespace này sạch sẽ và không lẫn lộn với các workloads ứng dụng và công cụ của bạn.

Namespace `kube-public` là một Namespace khác được tạo tự động có thể được sử dụng để lưu trữ các đối tượng bạn muốn có thể đọc và truy cập trên toàn bộ cụm, thậm chí cho các người dùng không xác thực.

Để tạo Namespace `kube-logging`, đầu tiên mở và chỉnh sửa một file có tên `kube-logging.yaml` bằng trình soạn thảo yêu thích của bạn, ví dụ như nano:

```sh
nano kube-logging.yaml
```

Trong trình soạn thảo của bạn, dán vào nội dung YAML sau:

```yaml
kind: Namespace
apiVersion: v1
metadata:
  name: kube-logging
```

Sau đó, lưu và đóng file lại.

Ở đây, chúng ta chỉ định loại đối tượng Kubernetes là một đối tượng Namespace. Để tìm hiểu thêm về đối tượng Namespace, hãy tham khảo phần hướng dẫn về Namespaces trong tài liệu chính thức của Kubernetes. Chúng ta cũng chỉ định phiên bản API của Kubernetes được sử dụng để tạo đối tượng (v1), và đặt tên là `kube-logging`.

Khi bạn đã tạo file đối tượng Namespace `kube-logging.yaml`, tạo Namespace bằng cách sử dụng kubectl với cờ -f để chỉ định tên file:

```sh
kubectl create -f kube-logging.yaml
```

Bạn sẽ thấy kết quả đầu ra sau:

```
namespace/kube-logging created
```

Sau đó, xác nhận rằng Namespace đã được tạo thành công:

```sh
kubectl get namespaces
```

Lúc này, bạn sẽ thấy Namespace mới `kube-logging`:

```
NAME           STATUS    AGE
default        Active    23m
kube-logging   Active    1m
kube-public    Active    23m
kube-system    Active    23m
```

Chúng ta đã sẵn sàng để triển khai cụm Elasticsearch trong Namespace logging này. Đổi context qua kube-logging:

```sh
kubectl config set-context --current --namespace=kube-logging
```

### Bước 2 — Tạo Elasticsearch StatefulSet

Bây giờ chúng ta đã tạo Namespace để chứa stack logging, chúng ta có thể bắt đầu triển khai các thành phần của nó. Đầu tiên, chúng ta sẽ triển khai một cụm Elasticsearch với 3 node.

Trong hướng dẫn này, chúng ta sử dụng 3 Pod Elasticsearch để tránh vấn đề "split-brain" xảy ra trong các cụm nhiều node có sẵn cao. Ở mức cao, "split-brain" xảy ra khi một hoặc nhiều node không thể giao tiếp với các node khác, và nhiều "master" bị tách ra được bầu chọn. Với 3 node, nếu một node bị ngắt kết nối khỏi cụm tạm thời, hai node còn lại có thể bầu chọn một master mới và cụm có thể tiếp tục hoạt động trong khi node cuối cùng cố gắng tái kết nối. Để tìm hiểu thêm, hãy tham khảo tài liệu về cluster coordination trong Elasticsearch và Voting configurations.

#### Tạo Headless Service

Để bắt đầu, chúng ta sẽ tạo một dịch vụ Kubernetes headless có tên `elasticsearch` sẽ xác định một miền DNS cho 3 Pod. Một dịch vụ headless không thực hiện load balancing hoặc có một IP tĩnh; để tìm hiểu thêm về dịch vụ headless, hãy tham khảo tài liệu chính thức của Kubernetes.

Mở một file mới có tên `elasticsearch_svc.yaml` bằng trình soạn thảo yêu thích của bạn:

```sh
nano elasticsearch_svc.yaml
```

Dán vào nội dung YAML sau:

```yaml
kind: Service
apiVersion: v1
metadata:
  name: elasticsearch
  namespace: kube-logging
  labels:
    app: elasticsearch
spec:
  selector:
    app: elasticsearch
  clusterIP: None
  ports:
    - port: 9200
      name: rest
    - port: 9300
      name: inter-node
```

Sau đó, lưu và đóng file lại.

Chúng ta định nghĩa một Service có tên `elasticsearch` trong Namespace `kube-logging`, và gán cho nó nhãn `app: elasticsearch`. Chúng ta sau đó đặt `.spec.selector` thành `app: elasticsearch` để Service này sẽ chọn các Pod có nhãn `app: elasticsearch`. Khi chúng ta kết hợp StatefulSet Elasticsearch của mình với Service này, Service sẽ trả về các bản ghi DNS A trỏ đến các Pod Elasticsearch có nhãn `app: elasticsearch`.

Chúng ta sau đó đặt `clusterIP: None`, làm cho dịch vụ trở thành headless. Cuối cùng, chúng ta định nghĩa các cổng 9200 và 9300 được sử dụng để tương tác với API REST và cho giao tiếp giữa các node.

Tạo dịch vụ bằng cách sử dụng kubectl:

```sh
kubectl create -f elasticsearch_svc.yaml
```

Bạn sẽ thấy kết quả đầu ra sau:

```
service/elasticsearch created
```

Cuối cùng, kiểm tra lại rằng dịch vụ đã được tạo thành công bằng cách sử dụng kubectl get:

```sh
kubectl get services --

namespace=kube-logging
```

Bạn sẽ thấy kết quả đầu ra như sau:

```
NAME            TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)             AGE
elasticsearch   ClusterIP   None         <none>        9200/TCP,9300/TCP   1m
```

Chúng ta đã sẵn sàng để triển khai cụm Elasticsearch.

#### Tạo StatefulSet

Bây giờ chúng ta sẽ tạo một StatefulSet để triển khai các Pod Elasticsearch.

Mở một file mới có tên `elasticsearch_statefulset.yaml` bằng trình soạn thảo yêu thích của bạn:

```sh
nano elasticsearch_statefulset.yaml
```

Dán vào nội dung YAML sau:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: es-cluster
  namespace: kube-logging
spec:
  serviceName: elasticsearch
  replicas: 3
  selector:
    matchLabels:
      app: elasticsearch
  template:
    metadata:
      labels:
        app: elasticsearch
    spec:
      containers:
      - name: elasticsearch
        image: docker.elastic.co/elasticsearch/elasticsearch:7.2.0
        resources:
            limits:
              cpu: 1000m
            requests:
              cpu: 100m
        ports:
        - containerPort: 9200
          name: rest
          protocol: TCP
        - containerPort: 9300
          name: inter-node
          protocol: TCP
        volumeMounts:
        - name: data
          mountPath: /usr/share/elasticsearch/data
        env:
          - name: cluster.name
            value: k8s-logs
          - name: node.name
            valueFrom:
              fieldRef:
                fieldPath: metadata.name
          - name: discovery.seed_hosts
            value: "es-cluster-0.elasticsearch,es-cluster-1.elasticsearch,es-cluster-2.elasticsearch"
          - name: cluster.initial_master_nodes
            value: "es-cluster-0,es-cluster-1,es-cluster-2"
          - name: ES_JAVA_OPTS
            value: "-Xms512m -Xmx512m"
      initContainers:
      - name: fix-permissions
        image: busybox
        command: ["sh", "-c", "chown -R 1000:1000 /usr/share/elasticsearch/data"]
        securityContext:
          privileged: true
        volumeMounts:
        - name: data
          mountPath: /usr/share/elasticsearch/data
      - name: increase-vm-max-map
        image: busybox
        command: ["sysctl", "-w", "vm.max_map_count=262144"]
        securityContext:
          privileged: true
      - name: increase-fd-ulimit
        image: busybox
        command: ["sh", "-c", "ulimit -n 65536"]
        securityContext:
          privileged: true
  volumeClaimTemplates:
  - metadata:
      name: data
      labels:
        app: elasticsearch
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: do-block-storage
      resources:
        requests:
          storage: 100Gi
```

Sau đó, lưu và đóng file lại.

Trong file này, chúng ta định nghĩa một StatefulSet có tên `es-cluster` trong Namespace `kube-logging` với ba replicas. Chúng ta gán nhãn `app: elasticsearch` cho StatefulSet và các Pod của nó. Chúng ta sau đó định nghĩa các container sử dụng image Elasticsearch 7.2.0, mở các cổng 9200 và 9300, và mount một volume để lưu trữ dữ liệu Elasticsearch.

Các biến môi trường cấu hình cụm Elasticsearch của chúng ta như sau:

- `cluster.name` đặt tên cho cụm Elasticsearch của chúng ta.
- `node.name` sử dụng trường `metadata.name` để đặt tên cho các node Elasticsearch của chúng ta.
- `discovery.seed_hosts` định nghĩa các host seed để khởi tạo khám phá cụm.
- `cluster.initial_master_nodes` định nghĩa các node master ban đầu cho cụm.
- `ES_JAVA_OPTS` định nghĩa các tùy chọn Java cho Elasticsearch, bao gồm heap size tối thiểu và tối đa.
- `network.host` đặt host mạng là 0.0.0.0 để cho phép Elasticsearch lắng nghe trên tất cả các địa chỉ IP.

Phần volumeClaimTemplates định nghĩa PV lưu trữ, nếu chưa có tạo storageClass như dưới đây thì cần tạo PV và Storageclass tương ứng, ví dụ như sau:

```sh
// Tại máy worker, mount ổ đĩa, ví dụ như sau: 
sudo mount /dev/ubuntu-vg/lv-1 /mnt/disks/local-storage
// Hoặc mount tự động mỗi khi boot hệ thống, ví dụ như:
echo "/dev/ubuntu-vg/lv-1 /mnt/disks/local-storage ext4 defaults 0 0" >> /etc/fstab

// Tạo các folder phục vụ cho pv:
mkdir /mnt/disks/local-storage/efk-pv/data-cluster-01
mkdir /mnt/disks/local-storage/efk-pv/data-cluster-02
mkdir /mnt/disks/local-storage/efk-pv/data-cluster-03

// Cấp quyền
chown 1000:1000 /mnt/disks/local-storage/efk-pv/data-cluster-01
chown 1000:1000 /mnt/disks/local-storage/efk-pv/data-cluster-02
chown 1000:1000 /mnt/disks/local-storage/efk-pv/data-cluster-03
```

Tạo storage class:

```yaml       
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
```

Tiếp theo, tạo pv: 

```yaml                                          
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-pvc1
spec:
  capacity:
    storage: 9Gi
  accessModes:
    - ReadWriteOnce
  storageClassName: local-storage
  local:
    path:  /mnt/disks/local-storage/efk-pv/data-cluster-01
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - vnpt

```

Tiến hành tương tự cho pv2, pv3.


```yaml


```

Cuối cùng, chúng ta định nghĩa một `volumeClaimTemplates` để yêu cầu 1Gi lưu trữ cho mỗi Pod Elasticsearch.

Tạo StatefulSet bằng cách sử dụng kubectl:

```sh
kubectl create -f elasticsearch_statefulset.yaml
```

Bạn sẽ thấy kết quả đầu ra sau:

```
statefulset.apps/elasticsearch created
```

Kiểm tra các Pod Elasticsearch của bạn bằng cách sử dụng kubectl get:

```sh
kubectl get pods --namespace=kube-logging
```

Bạn sẽ thấy kết quả đầu ra tương tự như sau khi các Pod đang được tạo:

```
NAME              READY   STATUS            RESTARTS   AGE
elasticsearch-0   0/1     ContainerCreating   0          10s
elasticsearch-1   0/1     Pending             0          10s
elasticsearch-2   0/1     Pending             0          10s
```

Sau một vài phút, kiểm tra lại các Pod để đảm bảo chúng đang chạy:

```sh
kubectl get pods --namespace=kube-logging
```

Bạn sẽ thấy kết quả đầu ra tương tự như sau khi các Pod đã sẵn sàng:

```
NAME              READY   STATUS    RESTARTS   AGE
elasticsearch-0   1/1     Running   0          1m
elasticsearch-1   1/1     Running   0          1m
elasticsearch-2   1/1     Running   0          1m
```

Bây giờ, cụm Elasticsearch của bạn đã được triển khai và sẵn sàng để nhận log.

### Bước 3 — Tạo Deployment và Service cho Kibana

Tiếp theo, chúng ta sẽ triển khai Kibana để hiển thị và truy vấn dữ liệu từ Elasticsearch qua giao diện web.

#### Tạo file YAML cho Kibana Deployment

Mở một file mới, ví dụ `kibana_deployment.yaml`, và thêm vào nội dung sau:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kibana
  namespace: kube-logging
  labels:
    app: kibana
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kibana
  template:
    metadata:
      labels:
        app: kibana
    spec:
      containers:
      - name: kibana
        image: docker.elastic.co/kibana/kibana:7.2.0
        resources:
          limits:
            cpu: 1000m
          requests:
            cpu: 100m
        env:
          - name: ELASTICSEARCH_URL
            value: http://elasticsearch:9200
        ports:
        - containerPort: 5601
```

Lưu ý rằng chúng ta đang sử dụng Docker image của Kibana từ Elastic và tham chiếu đến Elasticsearch qua URL `http://elasticsearch:9200`, trong đó `elasticsearch` là tên Service của Elasticsearch mà chúng ta đã tạo trước đó.

Lưu và đóng file lại. Sau đó, tạo Deployment cho Kibana bằng cách sử dụng kubectl:

```sh
kubectl create -f kibana_deployment.yaml
```

Bạn sẽ thấy kết quả đầu ra sau:

```
deployment.apps/kibana created
```

Kiểm tra Pod Kibana của bạn bằng cách sử dụng kubectl get:

```sh
kubectl get pods --namespace=kube-logging
```

Bạn sẽ thấy kết quả đầu ra tương tự như sau khi Pod Kibana đang được tạo:

```
NAME                     READY   STATUS              RESTARTS   AGE
elasticsearch-0          1/1     Running             0          4m
elasticsearch-1          1/1     Running             0          4m
elasticsearch-2          1/1     Running             0          4m
kibana-5d6d66d9d-5dx9k   0/1     ContainerCreating   0          10s
```

Sau một vài phút, kiểm tra lại Pod Kibana để đảm bảo nó đang chạy:

```sh
kubectl get pods --namespace=kube-logging
```

Bạn sẽ thấy kết quả đầu ra tương tự như sau khi Pod Kibana đã sẵn sàng:

```
NAME                     READY   STATUS    RESTARTS   AGE
elasticsearch-0          1/1     Running   0          5m
elasticsearch-1          1/1     Running   0          5m
elasticsearch-2          1/1     Running   0          5m
kibana-5d6d66d9d-5dx9k   1/1     Running   0          1m
```

#### Tạo file YAML cho Kibana Service

Mở một file mới, ví dụ `kibana_service.yaml`, và thêm vào nội dung sau:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kibana
  namespace: kube-logging
  labels:
    app: kibana
spec:
  ports:
  - port: 5601
  selector:
    app: kibana

---
apiVersion: v1
kind: Service
metadata:
  name: kibana-lb
  namespace: kube-logging
spec:
  selector:
    app: kibana
  ports:
    - port: 5601
      targetPort: 5601
      protocol: TCP
      name: http
  type: LoadBalancer
```

Lưu và đóng file lại. Sau đó, tạo Service cho Kibana bằng cách sử dụng kubectl:

```sh
kubectl create -f kibana_service.yaml
```

Bạn sẽ thấy kết quả đầu ra sau:

```
service/kibana created
```

Kiểm tra lại Service Kibana của bạn bằng cách sử dụng kubectl get:

```sh
kubectl get services --namespace=kube-logging
```

Bạn sẽ thấy kết quả đầu ra tương tự như sau:

```
NAME            TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)          AGE
elasticsearch   ClusterIP      None             <none>          9200/TCP,9300/TCP   10m
kibana          LoadBalancer   10.96.190.44     <pending>       5601:30787/TCP     1m
```

Chờ một vài phút để LoadBalancer gán một địa chỉ IP

 bên ngoài. Sau đó, kiểm tra lại Service Kibana để lấy địa chỉ IP bên ngoài:

```sh
kubectl get services --namespace=kube-logging
```

Bạn sẽ thấy kết quả đầu ra tương tự như sau:

```
NAME            TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)          AGE
elasticsearch   ClusterIP      None             <none>          9200/TCP,9300/TCP   12m
kibana          LoadBalancer   10.96.190.44     203.0.113.10    5601:30787/TCP     3m
```

Mở trình duyệt web của bạn và truy cập địa chỉ IP bên ngoài của Kibana, ví dụ `http://203.0.113.10:5601`. Bạn sẽ thấy giao diện web của Kibana, nơi bạn có thể cấu hình và khám phá dữ liệu log của mình.

### Bước 4 — Tạo DaemonSet cho Fluentd

Trong hướng dẫn này, chúng ta sẽ cài đặt Fluentd dưới dạng một DaemonSet, một loại workload trong Kubernetes chạy một bản sao của Pod trên mỗi Node trong cụm Kubernetes. Bằng cách sử dụng bộ điều khiển DaemonSet này, chúng ta sẽ triển khai một Pod tác nhân ghi log Fluentd trên mọi node trong cụm. Để tìm hiểu thêm về kiến trúc ghi log này, tham khảo tài liệu chính thức của Kubernetes về "Sử dụng một tác nhân ghi log cho node".

Trong Kubernetes, các ứng dụng container hóa ghi log vào stdout và stderr sẽ có các luồng log của chúng bị bắt và chuyển hướng vào các file JSON trên các node. Pod Fluentd sẽ đọc các file log này, lọc các sự kiện log, chuyển đổi dữ liệu log, và gửi chúng đến backend ghi log Elasticsearch mà chúng ta đã triển khai ở Bước 2.

Bắt đầu bằng cách mở một file có tên là `fluentd.yaml` trong trình soạn thảo văn bản yêu thích của bạn:

```sh
nano fluentd.yaml
```

Tiếp theo, chúng ta sẽ dán các định nghĩa đối tượng Kubernetes vào file, từng khối một, cung cấp ngữ cảnh khi chúng ta tiếp tục. Trong hướng dẫn này, chúng ta sử dụng cấu hình DaemonSet của Fluentd được cung cấp bởi các nhà phát triển Fluentd.

Trước tiên, dán vào định nghĩa ServiceAccount sau:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fluentd
  namespace: kube-logging
  labels:
    app: fluentd
```

Ở đây, chúng ta tạo một Service Account có tên là `fluentd` mà các Pod Fluentd sẽ sử dụng để truy cập API Kubernetes. Chúng ta tạo nó trong Namespace `kube-logging` và gán nhãn `app: fluentd` cho nó.

Tiếp theo, dán vào khối ClusterRole sau:

```yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: fluentd
  labels:
    app: fluentd
rules:
- apiGroups:
  - ""
  resources:
  - pods
  - namespaces
  verbs:
  - get
  - list
  - watch
```

Ở đây, chúng ta định nghĩa một ClusterRole có tên là `fluentd` và cấp quyền `get`, `list`, và `watch` trên các đối tượng `pods` và `namespaces`.

Tiếp theo, dán vào khối ClusterRoleBinding sau:

```yaml
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: fluentd
roleRef:
  kind: ClusterRole
  name: fluentd
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: fluentd
  namespace: kube-logging
```

Trong khối này, chúng ta định nghĩa một ClusterRoleBinding có tên là `fluentd` để liên kết ClusterRole `fluentd` với Service Account `fluentd`.

Bây giờ chúng ta có thể bắt đầu dán vào spec DaemonSet thực tế:

```yaml
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd
  namespace: kube-logging
  labels:
    app: fluentd
spec:
  selector:
    matchLabels:
      app: fluentd
  template:
    metadata:
      labels:
        app: fluentd
    spec:
      serviceAccount: fluentd
      serviceAccountName: fluentd
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      containers:
      - name: fluentd
        image: fluent/fluentd-kubernetes-daemonset:v1.4.2-debian-elasticsearch-1.1
        env:
          - name:  FLUENT_ELASTICSEARCH_HOST
            value: "elasticsearch.kube-logging.svc.cluster.local"
          - name:  FLUENT_ELASTICSEARCH_PORT
            value: "9200"
          - name: FLUENT_ELASTICSEARCH_SCHEME
            value: "http"
          - name: FLUENTD_SYSTEMD_CONF
            value: disable
        resources:
          limits:
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 200Mi
        volumeMounts:
        - name: varlog
          mountPath: /var/log
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
      terminationGracePeriodSeconds: 30
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
```

Ở đây, chúng ta định nghĩa một DaemonSet có tên là `fluentd` trong Namespace `kube-logging` và gán nhãn `app: fluentd` cho nó.

    - `FLUENT_ELASTICSEARCH_HOST`: Chúng ta thiết lập giá trị này là địa chỉ dịch vụ headless Elasticsearch đã được định nghĩa trước đó: `elasticsearch.kube-logging.svc.cluster.local`.
    - `FLUENT_ELASTICSEARCH_PORT`: Chúng ta thiết lập giá trị này là cổng Elasticsearch đã cấu hình trước đó, 9200.
    - `FLUENT_ELASTICSEARCH_SCHEME`: Chúng ta thiết lập giá trị này là `http`.
    - `FLUENTD_SYSTEMD_CONF`: Chúng ta thiết lập giá trị này là `disable` để ngăn xuất ra thông tin liên quan đến systemd không được cài đặt trong container.

Chúng ta cũng thiết lập giới hạn bộ nhớ là 512 MiB cho Pod FluentD và đảm bảo nó có 0.1vCPU và 200MiB bộ nhớ.

Cuối cùng, chúng ta mount các đường dẫn `/var/log` và `/var/lib/docker/containers` của host vào container bằng cách sử dụng `volumeMounts`.

Lưu và đóng file lại.

Tổng quan file như sau:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fluentd
  namespace: kube-logging
  labels:
    app: fluentd
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: fluentd
  labels:
    app: fluentd
rules:
- apiGroups:
  - ""
  resources:
  - pods
  - namespaces
  verbs:
  - get
  - list
  - watch
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: fluentd
roleRef:
  kind: ClusterRole
  name: fluentd
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: fluentd
  namespace: kube-logging
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd
  namespace: kube-logging
  labels:
    app: fluentd
spec:
  selector:
    matchLabels:
      app: fluentd
  template:
    metadata:
      labels:
        app: fluentd
    spec:
      serviceAccount: fluentd
      serviceAccountName: fluentd
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      containers:
      - name: fluentd
        image: fluent/fluentd-kubernetes-daemonset:v1.4.2-debian-elasticsearch-1.1
        env:
          - name:  FLUENT_ELASTICSEARCH_HOST
            value: "elasticsearch.kube-logging.svc.cluster.local"
          - name:  FLUENT_ELASTICSEARCH_PORT
            value: "9200"
          - name: FLUENT_ELASTICSEARCH_SCHEME
            value: "http"
          - name: FLUENTD_SYSTEMD_CONF
            value: disable
        resources:
          limits:
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 200Mi
        volumeMounts:
        - name: varlog
          mountPath: /var/log
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
      terminationGracePeriodSeconds: 30
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
```

Bây giờ, triển khai DaemonSet bằng cách sử dụng kubectl:

```sh
kubectl create -f fluentd.yaml
```

Bạn sẽ thấy kết quả đầu ra sau:

```
serviceaccount/fluentd created
clusterrole.rbac.authorization.k8s.io/fluentd created
clusterrolebinding.rbac.authorization.k8s.io/fluentd created
daemonset.extensions/fluentd created
```

Kiểm tra xem DaemonSet đã triển khai thành công chưa bằng cách sử dụng kubectl:

```sh
kubectl get ds --namespace=kube-logging
```

Bạn sẽ thấy kết quả đầu ra tương tự như sau:

```
NAME      DESIRED   CURRENT   READY     UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
fluentd   3         3         3         3            3           <none>          58s
```

Điều này cho thấy có 3 Pod Fluentd đang chạy, tương ứng với số lượng nodes trong cụm Kubernetes của chúng ta.