import Foundation

enum DockerfileTemplates {

    // MARK: - Dockerfile

    static func dockerfile(appName: String) -> String {
        return """
        # Build stage
        FROM swift:6.0-noble AS build
        WORKDIR /app
        COPY Package.swift Package.resolved ./
        RUN swift package resolve
        COPY . .
        RUN swift build -c release

        # Runtime stage
        FROM ubuntu:noble
        RUN apt-get update && apt-get install -y libcurl4 && rm -rf /var/lib/apt/lists/*
        COPY --from=build /app/.build/release/\(appName) /usr/local/bin/app
        COPY --from=build /app/Public /app/Public
        EXPOSE 8080
        ENV PEREGRINE_HOST=0.0.0.0
        ENV PEREGRINE_PORT=8080
        ENV PEREGRINE_ENV=prod
        ENTRYPOINT ["app"]
        """
    }

    // MARK: - .dockerignore

    static func dockerignore() -> String {
        return """
        .build/
        .swiftpm/
        .git/
        *.xcodeproj
        DerivedData/
        """
    }
}
