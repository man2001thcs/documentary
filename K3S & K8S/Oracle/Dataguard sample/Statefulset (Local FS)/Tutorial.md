# Hướng dẫn triển khai Oracle dataguard với k3s / k8s

> [!IMPORTANT] 
> Lưu ý: Hiện tại bản này của oracle image không hoạt động tốt lắm với Longhorn do vấn đề liên quan tới hệ thống file & quyền, nên ví dụ này sử dụng local file system.

> Hướng dẫn này phục vụ test & học hỏi là chính, không nên dùng trong production.

## Bước 1: Tạo pv & pvc local trên node, dựa trên đường link file system và lock vào node cố định qua affinity.

``` yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: dg11-pv
spec:
  capacity:
    storage: 70Gi
  accessModes:
  - ReadWriteMany
  storageClassName: oracle-db-sc
  local:
    path: /opt/oradata/dg11 # Vị trí lưu trữ trên file system của node (Set quyền đầy đủ)
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - emr-local-1 # Lock vào node dựa trên tên node 
```

Tạo pvc

``` yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dg11-pvc
  namespace: oracle-dg
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: oracle-db-sc
  resources:
    requests:
      storage: 70Gi
```

Đây là mẫu cho Primary, tạo tương tự cho replica. Có thể tham khảo file 0.local-pvc.yaml.

## Bước 2: Tạo pod helper chọc vào 2 PV trên (Cơ chế ReadWriteMany). Qua node này có thể xem FS của 2 pod dùng cho db sau này.

## Bước 3: Chạy cùng lúc 2 file tạo statefulset cho main và replica (2.statefulset-main.yaml và 3.statefulset-replica.yaml).

Phần tạo db của main sẽ khá lâu nên phải chờ tầm 15-20p.

Sau khi check log tạo thành công, thực hiện backup sang replica từ primary bằng rman trong terminal của primary (Dùng giao diện rancher hoặc vào bằng lệnh kubect exec -it <Tên pod> -n <Tên namespace> -- /bin/bash):

``` sh
rman target sys/$ORACLE_PWD@$ORACLE_SID auxiliary sys/$ORACLE_PWD@$DG_TARGET log=$ORACLE_BASE/cfgtoollogs/rmanduplicate/$ORACLE_SID.log <<EOF
duplicate target database
      for standby
     from active database
          dorecover
          spfile set db_unique_name='$DG_TARGET'
          nofilenamecheck;
EOF
```

Lưu lại spfile của Replica trong terminal của Replica, từ "$ORACLE_HOME/dbs/spfile$ORACLE_SID.ora" sang "/opt/oracle/oradata/dbconfig/$ORACLE_SID/spfile$ORACLE_SID.ora".

### Bật db replica ở trạng thái readonly:

``` sh
sqlplus / as sysdba;
``` 

``` sql
alter database open;
ALTER PLUGGABLE DATABASE $ORACLE_PDB OPEN READ ONLY;
alter database recover managed standby database disconnect from session;
```

EOF

### Chạy thiết lập ship redo log từ primary sang replica:

Vào primary terminal, gõ:

``` sh
sqlplus / as sysdba;
```

``` sql

ALTER SYSTEM SET log_archive_config='dg_config=(DG11,dg21)' SCOPE=BOTH;

ALTER SYSTEM SET log_archive_dest_2='service="dg21" ASYNC NOAFFIRM delay=0 optional compression=disable max_failure=0 reopen=300 db_unique_name="dg21" net_timeout=120 valid_for=(online_logfile,all_roles)' SCOPE=BOTH;

ALTER SYSTEM SET log_archive_dest_state_2='ENABLE' SCOPE=BOTH;

ALTER SYSTEM SET service_names='DG11,DG11PDB1' SCOPE=BOTH;

### On primary, re-sync with standby
ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_2 = ENABLE;
```

Sau cụm lệnh này, redo log sẽ ship sang bên Replica để apply.

Kiểm tra tình trạng apply redo logs: 

``` sql
SELECT THREAD#, SEQUENCE#, APPLIED, COMPLETION_TIME
FROM V$ARCHIVED_LOG
ORDER BY SEQUENCE#;
```

### Test

Case test: Tạo datafile ở primary, rồi sang replica xem nó đã được tạo chưa.

``` sh
sqlplus / as sysdba;
```

``` sql
alter session set container='DG11PDB1';

CREATE TABLESPACE PRAISE_THE_BLOOD DATAFILE '/opt/oracle/oradata/DG11/datafile/bloodborne-1.dbf' SIZE 500M AUTOEXTEND ON NEXT 100M MAXSIZE UNLIMITED;

ALTER TABLESPACE PRAISE_THE_BLOOD ADD DATAFILE '/opt/oracle/oradata/DG11/datafile/bloodborne-2.dbf' SIZE 500M AUTOEXTEND ON NEXT 100M MAXSIZE UNLIMITED;
```

Xong, sang FS của replica theo đường link tương tự /opt/oracle/oradata/DG11/datafile check xem file dược tạo chưa. Nếu tạo được thì setup thành công.