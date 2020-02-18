# Build
FROM openjdk:8-jdk-alpine as builder
LABEL stage=builder
ENV FUSEKI_VERSION 3.13.1

# ----
# Install Maven
RUN apk add --no-cache curl tar bash git
ARG MAVEN_VERSION=3.6.3
ARG USER_HOME_DIR="/root"
RUN mkdir -p /usr/share/maven && \
    curl -fsSL http://apache.osuosl.org/maven/maven-3/$MAVEN_VERSION/binaries/apache-maven-$MAVEN_VERSION-bin.tar.gz | tar -xzC /usr/share/maven --strip-components=1 && \
    ln -s /usr/share/maven/bin/mvn /usr/bin/mvn
ENV MAVEN_HOME /usr/share/maven
ENV MAVEN_CONFIG "$USER_HOME_DIR/.m2"
# speed up Maven JVM a bit
ENV MAVEN_OPTS="-XX:+TieredCompilation -XX:TieredStopAtLevel=1"

RUN mkdir -p /usr/src && cd /usr/src
RUN git clone https://github.com/apache/jena.git /usr/src/jena
# WORKDIR /usr/src/jena
RUN cd /usr/src/jena && git checkout jena-${FUSEKI_VERSION} && mvn clean install -pl jena-fuseki2/jena-fuseki-geosparql -am

FROM openjdk:8-jdk-alpine
LABEL maintainer="<https://orcid.org/0000-0003-4091-6059>"
ENV FUSEKI_VERSION 3.13.1
# Installation folder
RUN mkdir /jena-fuseki
ENV FUSEKI_HOME /jena-fuseki

WORKDIR /jena-fuseki
COPY --from=builder /usr/src/jena/jena-fuseki2/jena-fuseki-geosparql/target/jena-fuseki-geosparql-${FUSEKI_VERSION}.jar /usr/local/bin/jena-fuseki-geosparql.jar

ENV GOSU_VERSION 1.10
RUN set -x \
    && apk add --no-cache --virtual .gosu-deps \
    dpkg \
    gnupg \
    openssl \
    curl \
    && dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')" \
    && wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch" \
    && wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc" \
    && export GNUPGHOME="$(mktemp -d)" \
    && gpg --keyserver ipv4.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
    && gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
    && pkill -9 gpg-agent \
    && rm -r "$GNUPGHOME" /usr/local/bin/gosu.asc \
    && chmod +x /usr/local/bin/gosu \
    && gosu nobody true \
    && apk del .gosu-deps

# Adding user without root privileges alongside a user group
RUN addgroup -S nonroot \
    && adduser -S -g nonroot nonroot

RUN echo "Apache Jena Fuseki Version ${FUSEKI_VERSION}"> /jena-version
# Config and data volume
# The volume needs to be set after the directory has been created to avoid
# permissions issues
#VOLUME /data/fuseki/fuseki_DB
#ENV FUSEKI_BASE /data/fuseki
COPY base.ttl /
#COPY docker-entrypoint.sh /jena-fuseki

EXPOSE 3030

ENTRYPOINT ["java", "-jar", "/usr/local/bin/jena-fuseki-geosparql.jar"]