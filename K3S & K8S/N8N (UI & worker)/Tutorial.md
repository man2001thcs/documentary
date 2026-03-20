# Hướng dẫn triển khai N8N HA với k3s / k8s

---
```md id="rq4"
Yêu cầu:
1. Postgres database (Bản 13 trở lên).
2. Redis.
```

Có thể dựng 2 yêu cầu trên theo mẫu 1.redis.yaml và 0.postgres.yaml. Lưu ý, chỗ  volume lưu trữ postgres phải trống để  khởi tạo, quyền được set theo nhóm 999:999 và đầy đủ quyền đọc ghi. Có thể tạo volume ReadWriteMany và dùng 1 pod ngoài để chọc vào thiết lập quyền.

Chạy 2 deploy của n8n main và n8n worker trong mẫu đính kèm. Lưu ý, khi main chạy lên xong mới chạy worker.
