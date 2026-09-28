# Remove the existing container if it already exists
docker rm -f helloworld 2>$null

# Download the latest HelloWorld image from Docker Hub
docker pull nunopacheco/helloworld:latest

# Start the HelloWorld container and map port 8080
docker run -d -p 8080:8080 --name helloworld nunopacheco/helloworld:latest