# Hướng dẫn cài đặt K3s

Cài đặt K3s và Rancher trên một server là một quy trình tương đối đơn giản. Dưới đây là hướng dẫn chi tiết để bạn thực hiện.

## Bước 1: Cài đặt K3s

K3s là một phiên bản nhẹ của Kubernetes, được thiết kế để đơn giản hóa việc triển khai. Để cài đặt K3s, bạn có thể làm theo các bước sau:

``` sh
sudo apt-get update
sudo apt-get upgrade -y
```

``` sh
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode=644 --disable traefik" K3S_NODE_NAME=<<node-name>> K3S_TOKEN=<<your-token>> sh -s - server --cluster-init
```

Kiểm tra trạng thái của K3s:

``` sh
sudo systemctl status k3s
```

Bổ sung thêm node machine vào cụm:

``` sh
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode=644 --disable traefik" K3S_NODE_NAME=<<node-name>>  K3S_TOKEN=<<your-token>> sh -s - agent --server https://<<node-server-ip>>:6443
``` 
Example: 
``` sh
#Example
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode=644 --disable traefik" K3S_NODE_NAME=emr-local-1 K3S_TOKEN=123@VnPT13579 sh -s - server --cluster-init
```



Cấu hình KUBECONFIG: Để sử dụng kubectl với K3s, bạn cần cấu hình biến môi trường KUBECONFIG.

``` sh
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

Nếu sử dụng linux distro, vui lòng cấp quyền cho file config trên: 

``` sh
sudo chmod 600 /etc/rancher/k3s/k3s.yaml
```

**Bạn có thể thêm dòng này vào file ~/.bashrc hoặc ~/.bash_profile để tự động cấu hình khi đăng nhập.**

## Bước 2: Cài đặt Helm

Helm là một công cụ quản lý các ứng dụng Kubernetes. Rancher có thể được cài đặt thông qua Helm.

``` sh

curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

# Thêm repo Rancher:

helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update

``` 
## Bước 3: Cài đặt Cert-Manager

Cert-Manager là một yêu cầu cần thiết để Rancher có thể quản lý chứng chỉ SSL. Gõ lần lượt các lệnh sau:

``` sh
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.5.3/cert-manager.crds.yaml
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.5.3
```

**Kiểm tra trạng thái của Cert-Manager:**

``` sh
kubectl get pods --namespace cert-manager
```

## Bước 4: Cài đặt Nginx ingress controller

``` sh
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install nginx-ingress ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace

```

## Bước 5: Cài đặt Rancher

Bây giờ bạn có thể cài đặt Rancher bằng Helm.
``` sh
kubectl create namespace cattle-system
``` sh
# Cài đặt Rancher:

helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --create-namespace \
  --set hostname=<<Your-domain>> \
  --set replicas=1 \
  --set ingress.ingressClassName=nginx

# Thay thế rancher.yourdomain.com bằng domain hoặc địa chỉ IP mà bạn sẽ sử dụng để truy cập Rancher. Nhớ add host vào etc/host để sử dụng local.

# Kiểm tra trạng thái của Rancher:

kubectl get pods --namespace cattle-system
``` 

## Bước 5: Truy cập Rancher

Sau khi Rancher đã được cài đặt và các pod đều đang chạy, bạn có thể truy cập Rancher thông qua trình duyệt web.

Bổ sung host Vào etc/host, nếu bạn sử dụng local.

    Mở trình duyệt web và truy cập:

    https://rancher.yourdomain.com (Hoặc domain bạn đã set trước đó)

    Thiết lập mật khẩu quản trị viên:
    Khi truy cập lần đầu tiên, bạn sẽ được yêu cầu thiết lập mật khẩu quản trị viên.

    Cấu hình chứng chỉ SSL:
    Nếu bạn sử dụng tên miền thật, bạn có thể cấu hình chứng chỉ SSL từ Let’s Encrypt hoặc nhà cung cấp khác để bảo mật kết nối.

## Tổng kết

Quá trình này sẽ giúp bạn cài đặt và cấu hình K3s và Rancher trên một server duy nhất. Rancher sẽ cung cấp cho bạn một giao diện người dùng mạnh mẽ để quản lý các cluster Kubernetes và các ứng dụng chạy trên đó.

