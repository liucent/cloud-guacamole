FROM guacamole/guacd:1.6.0

USER root

ENV GUAC_VERSION=1.6.0
ENV TOMCAT_VERSION=9.0.86
ENV CATALINA_HOME=/opt/tomcat
ENV GUACAMOLE_HOME=/etc/guacamole

# 1. 安装基础依赖
RUN apk add --no-cache \
    openjdk11-jre \
    postgresql \
    postgresql-contrib \
    supervisor \
    curl \
    tar \
    bash \
    su-exec \
    dos2unix

# 2. 安装并极限瘦身 Tomcat
RUN mkdir -p ${CATALINA_HOME} \
    && curl -sL "https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz" | tar -xz -C ${CATALINA_HOME} --strip-components=1 \
    && rm -rf ${CATALINA_HOME}/webapps/* ${CATALINA_HOME}/docs ${CATALINA_HOME}/examples ${CATALINA_HOME}/bin/*.bat \
    && curl -sL "https://archive.apache.org/dist/guacamole/${GUAC_VERSION}/binary/guacamole-${GUAC_VERSION}.war" -o ${CATALINA_HOME}/webapps/ROOT.war

# 3. 部署 JDBC 驱动及扩展 (保留官方 sql 文件)
RUN mkdir -p /etc/guacamole/extensions /etc/guacamole/lib /opt/guacamole/schema /var/lib/postgresql/data /run/postgresql \
    && curl -sL "https://archive.apache.org/dist/guacamole/${GUAC_VERSION}/binary/guacamole-auth-jdbc-${GUAC_VERSION}.tar.gz" | tar -xz -C /tmp \
    && cp /tmp/guacamole-auth-jdbc-${GUAC_VERSION}/postgresql/guacamole-auth-jdbc-postgresql-${GUAC_VERSION}.jar /etc/guacamole/extensions/ \
    && cp /tmp/guacamole-auth-jdbc-${GUAC_VERSION}/postgresql/schema/*.sql /opt/guacamole/schema/ \
    && curl -f -sSL "https://jdbc.postgresql.org/download/postgresql-42.7.3.jar" -o /etc/guacamole/lib/postgresql-jdbc.jar \
    && rm -rf /tmp/*

# 4. 复制配置文件与启动脚本
COPY guacamole.properties /etc/guacamole/guacamole.properties
COPY supervisord.conf /etc/supervisord.conf
COPY entrypoint.sh /entrypoint.sh

RUN dos2unix /entrypoint.sh && chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
