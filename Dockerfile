# Use OpenJDK base image
FROM openjdk:17-jdk-alpine

# Copy the JAR file into the container
COPY target/spring-boot-2-hello-world-1.0.2-SNAPSHOT.jar app.jar

# Expose port (Spring Boot default port is 8080)
EXPOSE 8080

# Run the JAR file
ENTRYPOINT ["java", "-jar", "/app.jar"]
