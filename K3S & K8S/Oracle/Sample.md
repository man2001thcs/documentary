# Sample oracle

## Test

``` sh
sqlplus / as sysdba;
```

### Tạo tablespace với datafile (Nhiều datafile con hoặc bigfile). Với datafile con thì có giới hạn kích thước từng file, cần bổ sung thêm khi đầy, ưu điểm sẽ truy xuất nhanh hơn. Còn Bigfile thì chỉ tạo 1 file duy nhất với 1 tablespace, nhưng sẽ chậm hơn khi kích thước ngày càng tăng.

Sample datafile:

``` sql
alter session set container='DG11PDB1';

CREATE TABLESPACE PRAISE_THE_BLOOD DATAFILE '/opt/oracle/oradata/DG11/datafile/bloodborne-1.dbf' SIZE 500M AUTOEXTEND ON NEXT 100M MAXSIZE UNLIMITED;

-- Bổ sung thêm datafile
ALTER TABLESPACE PRAISE_THE_BLOOD ADD DATAFILE '/opt/oracle/oradata/DG11/datafile/bloodborne-2.dbf' SIZE 500M AUTOEXTEND ON NEXT 100M MAXSIZE UNLIMITED;
```

Sample bigsmoke:

``` sql
CREATE BIGFILE TABLESPACE BIG_SMOKE
DATAFILE '/opt/oracle/oradata/DG11/datafile/bigsmoke.dbf' SIZE 100M
AUTOEXTEND ON NEXT 100M MAXSIZE UNLIMITED
EXTENT MANAGEMENT LOCAL
SEGMENT SPACE MANAGEMENT AUTO;
```

### Tạo user, bảng mẫu

``` sql
-- Chuyển sang plugged db
ALTER SESSION SET CONTAINER=DG11PDB1;

-- Tạo user chisa
create user chisa identified by "Chisathuathedeonaoduoc" default tablespace PRAISE_THE_BLOOD temporary tablespace temp;

-- Grant quyền tạo session cho chisa để truy cập được vào schema
grant create session to chisa;

GRANT CREATE ANY TABLE, CREATE ANY VIEW, CREATE ANY SEQUENCE, CREATE ANY PROCEDURE, CREATE ANY TRIGGER TO chisa;

-- Grant quyền sử dụng tablespace 
ALTER USER chisa QUOTA UNLIMITED ON PRAISE_THE_BLOOD;

-- Tạo bảng
CREATE TABLE employees (
    employee_id NUMBER,
    first_name VARCHAR2(50),
    last_name VARCHAR2(50),
    hire_date DATE
);

-- Insert vài record
INSERT INTO employees (employee_id, first_name, last_name, hire_date)
VALUES (1, 'John', 'Doe', SYSDATE);

INSERT INTO employees (employee_id, first_name, last_name, hire_date)
VALUES (2, 'Jane', 'Smith', SYSDATE);

INSERT INTO employees (employee_id, first_name, last_name, hire_date)
VALUES (3, 'Mike', 'Johnson', SYSDATE);
```

### Xóa redo log đã completed trên 3 ngày

``` sql
rman target /

-- Inside RMAN prompt:
DELETE NOPROMPT ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-3';
```

### Update database NVARCHAR size

``` sql

-- inside container
sqlplus / as sysdba

SHUTDOWN IMMEDIATE;
STARTUP UPGRADE;

ALTER SYSTEM SET max_string_size=EXTENDED SCOPE=SPFILE;

@?/rdbms/admin/utl32k.sql;

ALTER PLUGGABLE DATABASE ALL OPEN UPGRADE;

ALTER SESSION SET CONTAINER = DG11PDB1;
@?/rdbms/admin/utl32k.sql;

SHUTDOWN IMMEDIATE;
STARTUP;

ALTER PLUGGABLE DATABASE ALL OPEN;

@?/rdbms/admin/utlrp.sql;

```

### Import

create or replace directory DUMP_DIR as '/opt/oracle/oradata/dump';

``` sh
impdp \"sys@dg11pdb1 as sysdba\" \
  SCHEMAS=<<Tên schema import>> \
  DIRECTORY=DUMP_DIR \
  DUMPFILE=<<Tên dump file_1>>.dmp, <<Tên dump file_2>>.dmp \
  LOGFILE=<<Tên file log lưu lại quá trình import>>.log \
  REMAP_SCHEMA=<<Tên schema import>>:<<Tên schema cần map sang>>
```

### Export

Sample tạo 2 phần (2 file export):

``` sh
expdp \"sys@dg11pdb1 as sysdba\" \
  schemas=<<Tên schema cần export>> \
  directory=DUMP_DIR \
  dumpfile=<Tên file dump>>_%U.dmp \
  logfile=<<Tên file log>>.log \
  compression=all \
  parallel=2 \ 
  reuse_dumpfiles=no

```

Sample chỉ export METADATA (Cấu trúc, không bao gồm dữ liệu):

``` sh
expdp \"sys@dg11pdb1 as sysdba\" \
  schemas=<<Tên schema cần export>> \
  directory=DUMP_DIR \
  dumpfile=<Tên file dump>>_1.dmp \
  logfile=<<Tên file log>>.log \
  content=METADATA_ONLY

```