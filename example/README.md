This is a Docker Compose setup example that shows how to use the custom backups Docker image and script.

* This dumps a MySQL database (version `8.0`) and uploads it to a S3 storage bucket using our custom Docker image and script.
* The backup script configuration is done through the local `.env` file.
    * I recommend copying or renaming the [`.env.example`](./.env.example) file to `.env` and editing it to your needs.
* Make sure to change the database name and MySQL root password inside of the [`docker-compose.yml`](./docker-compose.yml) file.
* This setup assumes the custom Docker image was built as `db-backups:latest`.
* There are multiple mount points expected from the Docker Compose configuration.
    * [`./conf/my.cnf:/etc/mysql/my.cnf`](./conf/my.cnf): The MySQL server config file.
    * [`./db-data:/var/lib/mysql`](./db-data): The MySQL data directory (for persistent database storage).
    * [`./backup-logs:/var/log/backups`](./backup-logs/): The backup script's log directory (for persistent log storage).
* The main database container has a hostname of `db` while the backups container has a hostname of `db-backups`.
    * When setting the `DB_HOST` env variable, you should set it to `db` when using this setup.

## Creating A Custom User
Since the backups Docker container didn't have access to dump databases using the `root` user, I had to create a separate MySQL user that can backup the database(s).

If you're using an official MySQL image, you can access the container's shell using a command line below.

```bash
sudo docker exec -it example-db-1 bash
```

Once inside the container, you can access the MySQL CLI using a command like below (root user).

```bash
mysql -u root -p"<password>"
```

Then, to select the database you want to back up: 

```mysql
use <DB Name>;
```

Finally, you'll want to use the following commands to create a separate user for backing up the database and granting them access to the database you want to back up.

```mysql
# Create user.
CREATE USER 'backups'@'172.16.0.0/255.240.0.0' IDENTIFIED BY 'changeme';

# Grant permissions (with grant) to user on database we want to backup (test-db in our case).
# NOTE - In production, you'll probably only want to provide the required privileges to backup the database (read only) for better security, etc.
GRANT ALL PRIVILEGES ON `test-db`.* TO 'backups'@'172.16.0.0/255.240.0.0' WITH GRANT OPTION;

# Flush the privileges.
FLUSH PRIVILEGES;
```

You'll want to make sure the `DB_USER` AND `DB_PASS` env variables for the backup script are set to proper values based off of the inputs above.

**⚠️WARNING:** The above commands assume the backups Docker container resides in the `172.16.0.0/12` IP range (this is the most common case for users). Make sure to change it if you know the container resides in a different IP range through the Docker network.