# Airflow, plus Spark in local mode and the lake jobs. The same image runs in Compose and k3s.
FROM apache/airflow:3.4.0-python3.12

# Spark runs on the JVM. Java is copied from Temurin's image, which carries its own trust
# store: the base image is a hardened Debian where an apt-installed JRE ends up with an
# empty one, and then no HTTPS download works.
COPY --from=eclipse-temurin:21-jre /opt/java/openjdk /opt/java/openjdk
ENV JAVA_HOME=/opt/java/openjdk \
    PATH=/opt/java/openjdk/bin:${PATH}

USER root
# /lake is the local warehouse in Compose; creating it here, owned by the airflow user,
# gives the Compose volume mounted there the same owner.
RUN mkdir /lake && chown airflow:0 /lake
USER airflow

# Naming Airflow's own version stops pip from moving it while it installs the rest.
RUN pip install --no-cache-dir "apache-airflow==${AIRFLOW_VERSION}" \
      "pyspark==4.1.4" "psycopg[binary]~=3.2" "pytest>=8"

COPY --chown=airflow:0 botchat_lake /opt/botchat/botchat_lake
COPY --chown=airflow:0 dags /opt/botchat/dags
COPY --chown=airflow:0 tests /opt/botchat/tests
ENV PYTHONPATH=/opt/botchat \
    AIRFLOW__CORE__DAGS_FOLDER=/opt/botchat/dags \
    AIRFLOW__CORE__LOAD_EXAMPLES=False

# Download the Iceberg, AWS and Kafka jars now, so a job never waits on Maven Central.
RUN python -m botchat_lake.session

CMD ["airflow", "standalone"]
