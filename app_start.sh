#!/bin/bash
set -e 
POSTGRESQL_VERSION=10

#Check if Airflow Dir is present in Domino Project....if not create airflow directory
if [ ! -d $DOMINO_WORKING_DIR/airflow ]; then
	echo "Creating Airflow Directory"
    mkdir -p  $DOMINO_WORKING_DIR/airflow/{dags,logs,postgresql}
    #build, link and modify postgres config files.
    echo "Move postgresql files into Domino Directory" 
	sudo chmod 777 -R /etc/postgresql/$POSTGRESQL_VERSION/main/
	cp /etc/postgresql/$POSTGRESQL_VERSION/main/postgresql.conf "$DOMINO_WORKING_DIR"/airflow/postgresql/
	cp /etc/postgresql/$POSTGRESQL_VERSION/main/pg_hba.conf "$DOMINO_WORKING_DIR"/airflow/postgresql/
	#configure pg_hba.conf
	echo "Configure pg_hba.conf"
	sed -i '85s/peer/trust/' "$DOMINO_WORKING_DIR"/airflow/postgresql/pg_hba.conf
	sed -i '90s/peer/trust/' "$DOMINO_WORKING_DIR"/airflow/postgresql/pg_hba.conf
	sed -i '92s/md5/trust/' "$DOMINO_WORKING_DIR"/airflow/postgresql/pg_hba.conf
	#configue postgresql.conf file
	echo "Configure postgresql.conf"
	sed -i '59s/#listen_addresses/listen_addresses/' "$DOMINO_WORKING_DIR"/airflow/postgresql/postgresql.conf
	#remove old and link new
	rm /etc/postgresql/$POSTGRESQL_VERSION/main/postgresql.conf && ln -s $DOMINO_WORKING_DIR/airflow/postgresql/postgresql.conf /etc/postgresql/$POSTGRESQL_VERSION/main/postgresql.conf
	rm /etc/postgresql/$POSTGRESQL_VERSION/main/pg_hba.conf && ln -s $DOMINO_WORKING_DIR/airflow/postgresql/pg_hba.conf /etc/postgresql/$POSTGRESQL_VERSION/main/pg_hba.conf	
	
	#build Airflow config file
	echo "Create Airflow.cfg"
	export AIRFLOW_HOME=/home/ubuntu/airflow && airflow db init
	cp /home/ubuntu/airflow/airflow.cfg "$DOMINO_WORKING_DIR"/airflow/
	#configure and create symbolic link to new config file
	echo "Configure Airflow.cfg >>>>> Link File"
	#dag dir 
	sed -i -E "s#(dags_folder =).*#\1 "$DOMINO_WORKING_DIR"/airflow/dags#" "$DOMINO_WORKING_DIR"/airflow/airflow.cfg
	#log dir
	sed -i -E "s#(base_log_folder =).*#\1 "$DOMINO_WORKING_DIR"/airflow/logs#" "$DOMINO_WORKING_DIR"/airflow/airflow.cfg
	#proscess manager log
	sed -i -E "s#(dag_processor_manager_log_location =).*#\1 "$DOMINO_WORKING_DIR"/airflow/logs/dag_processor_manager/dag_processor_manager.log#" "$DOMINO_WORKING_DIR"/airflow/airflow.cfg
	#Executor
	sed -i -E "s#(executor =).*#\1 LocalExecutor#" "$DOMINO_WORKING_DIR"/airflow/airflow.cfg
	#DB connecion 
	sed -i -E "s#(sql_alchemy_conn =).*#\1 postgresql+psycopg2://airflow:airflow@localhost/airflow#" "$DOMINO_WORKING_DIR"/airflow/airflow.cfg
	#Load Examples
	sed -i -E "s#(load_examples =).*#\1 False#" "$DOMINO_WORKING_DIR"/airflow/airflow.cfg
	#Load default connections
	sed -i -E "s#(load_default_connections =).*#\1 False#" "$DOMINO_WORKING_DIR"/airflow/airflow.cfg
	#Expose Config file in UI
	sed -i -E "s#(expose_config =).*#\1 True#" "$DOMINO_WORKING_DIR"/airflow/airflow.cfg
	#Catchup by default
	sed -i -E "s#(catchup_by_default =).*#\1 False#" "$DOMINO_WORKING_DIR"/airflow/airflow.cfg
	
	#add demo DAGS
	curl https://raw.githubusercontent.com/Jphelps87/AirflowWorkspace/main/domino-pipeline.py --output "$DOMINO_WORKING_DIR"/airflow/dags/domino-pipeline.py
	curl https://raw.githubusercontent.com/Jphelps87/AirflowWorkspace/main/hello_world.py --output "$DOMINO_WORKING_DIR"/airflow/dags/hello_world.py

fi

#create DB in postgres
sudo chown -R postgres /mnt/airflow/postgresql/
sudo service postgresql start
echo "CREATE USER airflow with PASSWORD 'airflow'" | sudo sh -c 'sudo -u postgres psql'
echo "CREATE DATABASE airflow;" | sudo sh -c 'sudo -u postgres psql'
echo "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO airflow;" | sudo sh -c 'sudo -u postgres psql'
echo "link custom airflow.cfg"
#Create symbolic link and remove default file
FILE=/home/ubutu/airflow/airflow.cfg
if [ -f /home/ubuntu/airflow/airflow.cfg ]; then
        echo "removing old airflow.cfg file"
        rm  /home/ubuntu/airflow/airflow.cfg
fi
#build sub_domain url and refactor for each run.
sudo cp "$DOMINO_WORKING_DIR"/airflow/airflow.cfg /home/ubuntu/airflow/airflow.cfg
domino_url="base_url = https://$DOMAINNAME/$DOMINO_PROJECT_OWNER/$DOMINO_PROJECT_NAME/r/notebookSession/$DOMINO_RUN_ID"
sudo sed -i 's,base_url = http://localhost:8080,'"$domino_url"',' /home/ubuntu/airflow/airflow.cfg
sudo sed -i 's,web_server_port = 8080,web_server_port = 8888,' /home/ubuntu/airflow/airflow.cfg
# echo """enable_proxy_fix = True
# proxy_fix_x_for = 1
# proxy_fix_x_proto = 1
# proxy_fix_x_host = 1
# proxy_fix_x_port = 1 """ | sudo tee -a /home/ubuntu/airflow/airflow.cfg

echo "Domino URL"
actual= cat /home/ubuntu/airflow/airflow.cfg | grep base_url

airflow db init
airflow variables -s DOMINO_API_HOST $DOMINO_API_HOST
airflow variables -s DOMINO_USER_API_KEY $DOMINO_USER_API_KEY
#start airflow webserver and scheduler
echo "Starting up Airflow"
airflow webserver -p 8888 -H "0.0.0.0" &
airflow scheduler
