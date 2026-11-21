resource "aws_security_group" "db" {
  name        = "botchat-db"
  description = "Postgres, reachable only from the botchat instance"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_instance" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.instance.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

# Our own copy of the Postgres 17 settings, with logical replication on for Step 17's
# change data capture. Everything else keeps RDS's defaults, including rds.force_ssl = 1.
resource "aws_db_parameter_group" "main" {
  name   = "botchat-postgres17"
  family = "postgres17"

  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot" # only read at startup
  }

  # A replication slot whose reader has gone away keeps WAL forever; cap it at 2 GB.
  parameter {
    name         = "max_slot_wal_keep_size"
    value        = "2048" # MB
    apply_method = "immediate"
  }
}

resource "aws_db_instance" "main" {
  identifier     = "botchat"
  engine         = "postgres"
  engine_version = "17"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  # The instance's zone (public subnet 0): traffic between zones is slower and billed per GB.
  availability_zone      = local.azs[0]
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.main.name
  publicly_accessible    = false

  username                    = "botchat_admin"
  manage_master_user_password = true # RDS keeps the password in Secrets Manager

  backup_retention_period    = 7
  auto_minor_version_upgrade = true
  deletion_protection        = true
  skip_final_snapshot        = false
  final_snapshot_identifier  = "botchat-final"
}
