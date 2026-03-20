Good question — this is a **common issue with Oracle Data Guard**, especially when your **standby database** stops (for example: container restart, VM reboot, or manual shutdown).

Let’s go through what happens and what you should (and shouldn’t) do 👇

---

## ⚙️ When Standby Stops

If your **standby database** (physical standby) stops or its container is restarted, replication temporarily halts because the **redo apply** and **log shipping** processes stop.

When you start the standby again, it won’t automatically re-sync *until* both:

1. The standby database is **mounted in managed recovery mode**, and
2. The **primary can connect** and ship redo logs again.

---

## ✅ Basic Recovery Steps

### On **STANDBY**

1. **Start the database in MOUNT mode**

   ```sql
   sqlplus / as sysdba
   STARTUP MOUNT;
   ```

2. **Start managed recovery**

   ```sql
   ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT FROM SESSION;
   ```

   Or (for real-time apply):

   ```sql
   ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;
   ```

   🔸 `USING CURRENT LOGFILE` = real-time apply
   🔸 `DISCONNECT FROM SESSION` = runs in background

3. **Check status**

   ```sql
   SELECT PROCESS, STATUS, THREAD#, SEQUENCE# FROM V$MANAGED_STANDBY;
   ```

   You should see:

   ```
   MRP0     APPLYING_LOG   1   105
   RFS      RECEIVING      1   106
   ```

   (Means it’s receiving and applying redo from the primary again.)

---

### On **PRIMARY**

Usually, you don’t need to do anything, *as long as:*

* `LOG_ARCHIVE_DEST_STATE_2` is still `ENABLE`, and
* the standby service (`tnsnames.ora` entry or listener) is reachable.

To verify:

```sql
SHOW PARAMETER log_archive_dest_state_2;
```

If it shows `DEFER`, re-enable it:

```sql
ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_2=ENABLE;
```

You can also check redo shipping:

```sql
SELECT DEST_ID, STATUS, ERROR FROM V$ARCHIVE_DEST_STATUS;
```

---

## 🧭 If Standby Missed Redo Logs

If the standby was **offline for a long time**, it may have missed archived logs.

Check for gaps:

```sql
SELECT * FROM V$ARCHIVE_GAP;
```

If a gap exists, manually copy the missing archived redo logs from primary to standby (the `.arc` files) and register them:

```sql
ALTER DATABASE REGISTER PHYSICAL LOGFILE '/path/to/missing_log.arc';
```

Then restart recovery:

```sql
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;
```

---

## 🧩 In Short

| Situation            | What to Do                                                |
| -------------------- | --------------------------------------------------------- |
| Standby restarted    | Mount & start managed recovery                            |
| Primary restarted    | Nothing special; ensure `log_archive_dest_state_2=ENABLE` |
| Network lost briefly | Auto-recovers once connection resumes                     |
| Standby missed logs  | Copy missing `.arc` files and register manually           |

---

## 🔍 Optional: Check Sync Status

On primary:

```sql
SELECT DEST_ID, STATUS, ERROR, GAP_STATUS FROM V$ARCHIVE_DEST_STATUS WHERE DEST_ID=2;
```

On standby:

```sql
SELECT SEQUENCE#, APPLIED FROM V$ARCHIVED_LOG ORDER BY SEQUENCE#;
```

You should see the latest sequence applied shortly after it’s shipped.

---

Would you like me to give you a **bash script** that automatically checks if your standby is out of sync and restarts recovery if needed (for container environments like Docker or Kubernetes)?
It’s very handy if your standby container restarts often.
