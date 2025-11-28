package main

import (
	"fmt"
	"github.com/gin-gonic/gin"
)

// The main function of the NetDaemon microservice.
func main() {
	// Create a new Gin router with default middleware.
	r := gin.Default()

	// Define a GET endpoint for "/ping".
	r.GET("/ping", func(c *gin.Context) {
		// Respond with a JSON object containing the message "pong".
		c.JSON(200, gin.H{
			"message": "pong",
		})
	})

	// Print a message to the console indicating that the service is starting.
	fmt.Println("NetDaemon starting...")
	// The following line is commented out to prevent the build from blocking.
	// r.Run()
}
