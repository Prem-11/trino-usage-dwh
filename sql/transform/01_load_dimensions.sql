-- Full refresh of dimensions from the HR/LDAP export and table catalog.
-- Small tables, so delete + reload is simple and always correct.

DELETE FROM core.dim_team;
INSERT INTO core.dim_team
SELECT team_id, team_name, department
FROM read_csv('{ref_dir}/teams.csv', header = true,
     columns = {'team_id': 'VARCHAR', 'team_name': 'VARCHAR', 'department': 'VARCHAR'});
-- Special team for users missing from HR data (they are never dropped)
INSERT INTO core.dim_team VALUES ('unassigned', 'Unassigned', NULL);

DELETE FROM core.dim_user;
INSERT INTO core.dim_user
SELECT user_name, email, is_service_account
FROM read_csv('{ref_dir}/users.csv', header = true,
     columns = {'user_name': 'VARCHAR', 'email': 'VARCHAR', 'is_service_account': 'BOOLEAN'});

DELETE FROM core.bridge_user_team;
INSERT INTO core.bridge_user_team
SELECT user_name, team_id, valid_from, valid_to
FROM read_csv('{ref_dir}/user_team_history.csv', header = true,
     columns = {'user_name': 'VARCHAR', 'team_id': 'VARCHAR', 'valid_from': 'DATE', 'valid_to': 'DATE'});

DELETE FROM core.dim_table;
INSERT INTO core.dim_table
SELECT table_id, catalog, schema_name, table_name, owner_team_id, description, created_date
FROM read_csv('{ref_dir}/tables.csv', header = true,
     columns = {'table_id': 'VARCHAR', 'catalog': 'VARCHAR', 'schema_name': 'VARCHAR',
                'table_name': 'VARCHAR', 'owner_team_id': 'VARCHAR',
                'description': 'VARCHAR', 'created_date': 'DATE'});