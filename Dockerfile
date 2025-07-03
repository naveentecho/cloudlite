FROM openjdk:17-jdk-slim
RUN pwd
COPY ./target/spring-boot-2-hello-world-1.0.2-SNAPSHOT.jar app.jar

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app.jar"]
