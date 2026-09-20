FROM maven:3.9.9-eclipse-temurin-21@sha256:3a4ab3276a087bf276f79cae96b1af04f53731bec53fb2e651aca79e4b10211e AS build
WORKDIR /workspace
COPY pom.xml .
COPY src src
COPY deploy/maven-settings.xml /tmp/maven-settings.xml
RUN --mount=type=cache,target=/root/.m2 mvn -s /tmp/maven-settings.xml -B -DskipTests package

FROM eclipse-temurin:21-jre@sha256:49e21e16e3c86eb7816a44a67549910ed090fbeb40c29c525d58bf5e02e91b0f
RUN apt-get update && apt-get install -y --no-install-recommends openssl curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /workspace/target/*.jar app.jar
COPY deploy/backend-entrypoint.sh /app/entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["sh", "/app/entrypoint.sh"]
