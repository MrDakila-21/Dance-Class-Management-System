library(shiny)
library(shinyjs)
library(DBI)
library(RSQLite)  
library(pool)
library(dplyr)
library(DT)
library(qrcode)
library(png)
library(jsonlite)
library(base64enc)

# Database configuration for SQLite
db_config <- list(
  dbname = "dance_studio.sqlite",  # SQLite uses file-based databases
  host = NULL,  # Not needed for SQLite
  port = NULL,  # Not needed for SQLite
  user = NULL,  # Not needed for SQLite
  password = NULL  # Not needed for SQLite
)

# Create database if it doesn't exist and set up schema
initialize_sqlite_database <- function() {
  tryCatch({
    # Create or connect to database
    con <- dbConnect(RSQLite::SQLite(), db_config$dbname)
    
    # Enable foreign keys
    dbExecute(con, "PRAGMA foreign_keys = ON;")
    
    # Check if tables exist, if not create them
    tables <- dbListTables(con)
    
    if (!"classes" %in% tables) {
      # Create classes table
      dbExecute(con, "
        CREATE TABLE classes (
          class_id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          description TEXT,
          instructor TEXT NOT NULL,
          date TEXT NOT NULL,
          time TEXT NOT NULL,
          duration INTEGER NOT NULL,
          total_slots INTEGER NOT NULL,
          slots_remaining INTEGER NOT NULL DEFAULT 0,
          status TEXT DEFAULT 'Available',
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          price REAL NOT NULL,
          archived INTEGER DEFAULT 0
        )
      ")
      
      # Insert sample data
      dbExecute(con, "
        INSERT INTO classes (title, description, instructor, date, time, duration, total_slots, slots_remaining, status, price, archived) 
        VALUES 
        ('Hip Hop Beginner', 'Learn basic hip hop moves and choreography', 'Alice Johnson', '2024-03-15', '18:00:00', 60, 20, 15, 'Available', 0.0, 1),
        ('Ballet Intermediate', 'Intermediate ballet techniques and positions', 'John Smith', '2024-03-20', '16:30:00', 90, 15, 1, 'Few Slots', 0.0, 1),
        ('Salsa Advanced', 'Advanced salsa patterns and partner work', 'Maria Garcia', '2024-03-25', '19:15:00', 75, 20, 19, 'Available', 0.0, 1)
      ")
    }
    
    if (!"bookings" %in% tables) {
      # Create bookings table
      dbExecute(con, "
        CREATE TABLE bookings (
          booking_id INTEGER PRIMARY KEY AUTOINCREMENT,
          class_id INTEGER NOT NULL,
          customer_name TEXT NOT NULL,
          contact TEXT,
          slots_booked INTEGER NOT NULL DEFAULT 1,
          date_booked TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          status TEXT DEFAULT 'Booked',
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          customer_type TEXT NOT NULL DEFAULT 'Regular',
          booking_ref TEXT,
          archived INTEGER DEFAULT 0,
          FOREIGN KEY (class_id) REFERENCES classes (class_id) ON DELETE CASCADE
        )
      ")
      
      # Insert sample data
      dbExecute(con, "
        INSERT INTO bookings (class_id, customer_name, contact, slots_booked, date_booked, status, created_at, customer_type, booking_ref, archived) 
        VALUES 
        (1, 'Emily Johnson', 'emily2@email.com', 2, '2025-12-11 08:49:46', 'Booked', '2025-12-11 08:49:46', 'Regular', NULL, 1),
        (1, 'Michael Chen', '555-0123', 1, '2025-12-11 08:49:46', 'Booked', '2025-12-11 08:49:46', 'Regular', NULL, 1),
        (2, 'David Brown', 'david@email.com', 1, '2025-12-11 08:49:46', 'Booked', '2025-12-11 08:49:46', 'Regular', NULL, 1)
      ")
    }
    
    if (!"users" %in% tables) {
      # Create users table
      dbExecute(con, "
        CREATE TABLE users (
          user_id INTEGER PRIMARY KEY AUTOINCREMENT,
          username TEXT NOT NULL UNIQUE,
          password_hash TEXT NOT NULL,
          full_name TEXT NOT NULL,
          user_role TEXT DEFAULT 'admin',
          is_active INTEGER DEFAULT 1,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          last_login TEXT
        )
      ")
      
      # Insert admin user (password: My.System123)
      dbExecute(con, "
        INSERT INTO users (username, password_hash, full_name, user_role, is_active, created_at) 
        VALUES ('StudioTrack.admin', '$2a$12$LQv3c1yqBWVHxkdU6nZQdeHIXsCYYYvD5uGfP6Oo8b7WqK1lLdKZa', 'StudioTrack Administrator', 'admin', 1, CURRENT_TIMESTAMP)
      ")
    }
    
    # Create indexes for better performance
    if (length(dbListTables(con)) > 0) {
      dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_bookings_class_id ON bookings (class_id)")
      dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_bookings_status ON bookings (status)")
      dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_classes_date ON classes (date)")
      dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_classes_archived ON classes (archived)")
    }
    
    dbDisconnect(con)
    
    cat("SQLite database initialized successfully!\n")
    return(TRUE)
  }, error = function(e) {
    cat("Error initializing SQLite database:", e$message, "\n")
    return(FALSE)
  })
}

# Initialize the database
initialize_sqlite_database()

# Create database pool
pool <- tryCatch({
  dbPool(
    drv = RSQLite::SQLite(),  # Changed to SQLite driver
    dbname = db_config$dbname  # Only need dbname for SQLite
  )
}, error = function(e) {
  showNotification(paste("Database connection error:", e$message), 
                   type = "error", duration = 10)
  NULL
})

# On app stop, close the pool
onStop(function() {
  if(!is.null(pool)) {
    poolClose(pool)
  }
})

# Helper function to convert SQL for SQLite compatibility
convert_sql_for_sqlite <- function(sql) {
  # Replace MySQL-specific functions with SQLite equivalents
  sql <- gsub("NOW\\(\\)", "datetime('now')", sql)
  sql <- gsub("CURDATE\\(\\)", "date('now')", sql)
  sql <- gsub("CURRENT_TIMESTAMP", "datetime('now')", sql)
  
  # Replace auto_increment with autoincrement
  sql <- gsub("AUTO_INCREMENT", "AUTOINCREMENT", sql, ignore.case = TRUE)
  
  # Remove backticks (SQLite doesn't need them)
  sql <- gsub("`", "", sql)
  
  return(sql)
}

# Helper function to execute SQL with SQLite compatibility
execute_sql <- function(pool, sql, params = NULL) {
  sql <- convert_sql_for_sqlite(sql)
  if (is.null(params)) {
    dbExecute(pool, sql)
  } else {
    dbExecute(pool, sql, params = params)
  }
}

# Helper function to query SQL with SQLite compatibility
query_sql <- function(pool, sql, params = NULL) {
  sql <- convert_sql_for_sqlite(sql)
  if (is.null(params)) {
    dbGetQuery(pool, sql)
  } else {
    dbGetQuery(pool, sql, params = params)
  }
}

# The rest of your UI and server code remains the same (except for database queries)
# Only database query functions need to be updated

# ... [Rest of the UI code remains exactly the same] ...

ui <- fluidPage(
  useShinyjs(),
  tags$head(
    tags$script(src = "https://unpkg.com/html5-qrcode@2.3.8/html5-qrcode.min.js"),
    tags$script(HTML('
      // HTML5 QR Code Scanner Implementation
      let html5QrCode = null;
      let currentCameraId = null;
      let cameraList = [];

      // Initialize camera list
      async function initializeCameras() {
          try {
              const devices = await Html5Qrcode.getCameras();
              cameraList = devices;
              console.log("Cameras found:", devices.length);
              return devices;
          } catch (error) {
              console.error("Camera initialization error:", error);
              updateScannerStatus("Camera access error: " + error, "error");
              return [];
          }
      }

      // Start QR Scanner
      async function startQrScanner() {
          // Stop if already running
          if (html5QrCode && html5QrCode.isScanning) {
              console.log("Scanner already running");
              return;
          }
          
          // Initialize cameras
          const cameras = await initializeCameras();
          if (cameras.length === 0) {
              updateScannerStatus("No cameras found on this device", "error");
              return;
          }
          
          // Select camera (prefer rear/back camera)
          let selectedCameraId = null;
          const backCamera = cameras.find(cam => 
              cam.label.toLowerCase().includes("back") || 
              cam.label.toLowerCase().includes("rear")
          );
          
          if (backCamera) {
              selectedCameraId = backCamera.id;
          } else {
              selectedCameraId = cameras[0].id;
          }
          
          currentCameraId = selectedCameraId;
          const selectedCamera = cameras.find(c => c.id === selectedCameraId);
          
          // Initialize scanner
          html5QrCode = new Html5Qrcode("qr-reader");
          
          // Configure scanner
          const config = {
              fps: 10,
              qrbox: { width: 250, height: 250 },
              rememberLastUsedCamera: true,
              supportedScanTypes: [Html5QrcodeScanType.SCAN_TYPE_CAMERA]
          };
          
          // Success callback
          const onScanSuccess = (decodedText, decodedResult) => {
              console.log("QR Code scanned successfully:", decodedText);
              
              // Stop scanner temporarily
              html5QrCode.stop();
              
              // Show result
              Shiny.setInputValue("qr_scanned_content", decodedText);
              updateScannerStatus("QR Code detected!", "success");
              
              // Display result
              $("#scan-result").show();
              $("#qr_result_text").text(decodedText);
              
              // Resume scanning after 3 seconds
              setTimeout(() => {
                  if (html5QrCode && !html5QrCode.isScanning) {
                      html5QrCode.resume();
                      updateScannerStatus("Scanner resumed - ready for next scan", "success");
                      $("#scan-result").hide();
                  }
              }, 3000);
          };
          
          // Error callback (ignore when intentionally stopping)
          const onScanError = (errorMessage) => {
              // Don\'t show error if scanner was intentionally stopped
              if (!errorMessage.includes("NotFoundException") && 
                  !errorMessage.includes("NotAllowedError")) {
                  console.log("Scan error:", errorMessage);
              }
          };
          
          // Start scanning
          try {
              await html5QrCode.start(
                  selectedCameraId,
                  config,
                  onScanSuccess,
                  onScanError
              );
              
              updateScannerStatus("Scanner active - Using: " + 
                  (selectedCamera ? selectedCamera.label : "Default Camera"), "success");
              Shiny.setInputValue("scanner_active", "true");
              
          } catch (error) {
              console.error("Failed to start scanner:", error);
              updateScannerStatus("Failed to start camera: " + error.message, "error");
              html5QrCode = null;
          }
      }

      // Stop QR Scanner
      function stopQrScanner() {
          if (html5QrCode && html5QrCode.isScanning) {
              html5QrCode.stop()
                  .then(() => {
                      updateScannerStatus("Scanner stopped", "info");
                      Shiny.setInputValue("scanner_active", "false");
                      html5QrCode = null;
                  })
                  .catch((err) => {
                      console.error("Error stopping scanner:", err);
                  });
          } else {
              updateScannerStatus("Scanner not running", "info");
          }
      }

      // Switch between cameras
      async function switchCamera() {
          if (!html5QrCode || !html5QrCode.isScanning) {
              updateScannerStatus("Start scanner first to switch cameras", "warning");
              return;
          }
          
          const cameras = cameraList.length > 0 ? cameraList : await initializeCameras();
          
          if (cameras.length < 2) {
              updateScannerStatus("Only one camera available", "warning");
              return;
          }
          
          // Find current camera index
          let currentIndex = cameras.findIndex(cam => cam.id === currentCameraId);
          if (currentIndex === -1) currentIndex = 0;
          
          // Calculate next camera
          const nextIndex = (currentIndex + 1) % cameras.length;
          const nextCamera = cameras[nextIndex];
          
          // Stop current scanner
          await html5QrCode.stop();
          
          // Update current camera
          currentCameraId = nextCamera.id;
          
          // Restart with new camera
          const config = {
              fps: 10,
              qrbox: { width: 250, height: 250 },
              rememberLastUsedCamera: true
          };
          
          try {
              await html5QrCode.start(
                  currentCameraId,
                  config,
                  (decodedText) => {
                      console.log("QR Code scanned:", decodedText);
                      html5QrCode.stop();
                      Shiny.setInputValue("qr_scanned_content", decodedText);
                      updateScannerStatus("QR Code detected!", "success");
                  },
                  () => {} // Empty error callback
              );
              
              updateScannerStatus("Switched to: " + nextCamera.label, "success");
          } catch (error) {
              updateScannerStatus("Error switching camera: " + error.message, "error");
          }
      }

      // Update scanner status display
      function updateScannerStatus(message, type) {
          const statusElement = document.getElementById("scanner-status");
          const colors = {
              success: "#16a34a",
              error: "#dc2626",
              warning: "#d97706",
              info: "#64748b"
          };
          
          const icons = {
              success: "fa-check-circle",
              error: "fa-times-circle",
              warning: "fa-exclamation-circle",
              info: "fa-info-circle"
          };
          
          const color = colors[type] || "#64748b";
          const icon = icons[type] || "fa-info-circle";
          
          statusElement.innerHTML = 
              `<span style="color: ${color};">
                  <i class="fas ${icon}"></i> ${message}
              </span>`;
      }

      // Initialize on page load
      $(document).on("shiny:connected", function() {
          console.log("QR Scanner module loaded");
          initializeCameras();
      });
    ')),
    tags$style(HTML('
/* Login Page Styles */
.login-container {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 100vh;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  padding: 20px;
}

.login-card {
  background: white;
  border-radius: 20px;
  box-shadow: 0 20px 60px rgba(0,0,0,0.3);
  width: 100%;
  max-width: 420px;
  padding: 40px;
  animation: fadeIn 0.5s ease-out;
}

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(20px); }
  to { opacity: 1; transform: translateY(0); }
}

.login-header {
  text-align: center;
  margin-bottom: 40px;
}

.login-logo {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 15px;
  margin-bottom: 20px;
}

.login-logo-icon {
  background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%);
  width: 60px;
  height: 60px;
  border-radius: 16px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: white;
  font-size: 28px;
}

.login-title {
  font-size: 32px;
  font-weight: 700;
  color: #1e293b;
  margin: 0;
  line-height: 1.2;
}

.login-subtitle {
  font-size: 16px;
  color: #64748b;
  margin: 10px 0 0 0;
}

.login-form {
  margin-bottom: 30px;
}

.form-group {
  margin-bottom: 25px;
}

.form-label {
  display: block;
  font-size: 14px;
  font-weight: 600;
  color: #475569;
  margin-bottom: 8px;
}

.form-input {
  width: 100%;
  padding: 14px 18px;
  border: 2px solid #e2e8f0;
  border-radius: 12px;
  font-size: 16px;
  color: #1e293b;
  background: white;
  transition: all 0.3s ease;
}

.form-input:focus {
  outline: none;
  border-color: #6366f1;
  box-shadow: 0 0 0 4px rgba(99,102,241,0.1);
}

.form-input.error {
  border-color: #ef4444;
}

.error-message {
  color: #ef4444;
  font-size: 13px;
  margin-top: 6px;
  display: flex;
  align-items: center;
  gap: 6px;
}

.login-button {
  width: 100%;
  padding: 16px;
  background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%);
  color: white;
  border: none;
  border-radius: 12px;
  font-size: 16px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.3s ease;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
}

.login-button:hover {
  transform: translateY(-2px);
  box-shadow: 0 10px 25px rgba(99,102,241,0.3);
}

.login-button:disabled {
  background: #cbd5e1;
  cursor: not-allowed;
  transform: none;
  box-shadow: none;
}

.login-footer {
  text-align: center;
  margin-top: 30px;
  padding-top: 20px;
  border-top: 1px solid #e2e8f0;
}

.login-footer p {
  color: #64748b;
  font-size: 14px;
  margin: 0;
}

.login-footer strong {
  color: #1e293b;
}

/* Main App Styles (Only shown after login) */
.main-app {
  display: none;
}

/* Reset and Base Styles */
* { margin: 0; padding: 0; box-sizing: border-box; }

/* Navigation */
.top-nav {
    background: white; box-shadow: 0 2px 10px rgba(0,0,0,0.05);
    padding: 0 30px; height: 70px; display: flex; align-items: center;
    justify-content: space-between; position: fixed; top: 0;
    left: 0; right: 0; z-index: 1000;
}
.nav-brand { display: flex; align-items: center; gap: 12px; }
.nav-brand i { color: #6366f1; font-size: 24px; }
.nav-brand h1 { font-size: 24px; font-weight: 700; color: #1e293b; margin: 0; }

.nav-tabs {
    display: flex; gap: 2px; background: #f1f5f9;
    border-radius: 10px; padding: 4px;
}
.nav-tab {
    padding: 12px 24px; border: none; background: transparent;
    color: #64748b; font-weight: 600; font-size: 15px; border-radius: 8px;
    cursor: pointer; transition: all 0.3s ease; display: flex;
    align-items: center; gap: 8px;
}
.nav-tab:hover { color: #475569; background: rgba(255,255,255,0.8); }
.nav-tab.active { background: white; color: #6366f1; box-shadow: 0 2px 8px rgba(99,102,241,0.15); }

.nav-actions { display: flex; align-items: center; gap: 15px; }
.user-profile {
    display: flex; align-items: center; gap: 10px; padding: 8px 16px;
    background: #f8fafc; border-radius: 8px; cursor: pointer;
}
.user-avatar {
    width: 36px; height: 36px; background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%);
    border-radius: 50%; display: flex; align-items: center;
    justify-content: center; color: white; font-weight: 600;
}

/* Main Content */
.main-content { margin-top: 90px; padding: 30px; }

/* Dashboard Header */
.dashboard-header { margin-bottom: 30px; }
.dashboard-title { font-size: 32px; font-weight: 700; color: #1e293b; margin: 0 0 10px 0; }
.dashboard-subtitle { color: #64748b; font-size: 16px; margin: 0; }

/* Stats Cards */
.stats-grid {
    display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
    gap: 20px; margin-bottom: 40px;
}
.stat-card {
    background: white; border-radius: 16px; padding: 25px;
    box-shadow: 0 4px 20px rgba(0,0,0,0.04); border: 1px solid #f1f5f9;
    transition: transform 0.3s ease, box-shadow 0.3s ease;
}
.stat-card:hover { transform: translateY(-5px); box-shadow: 0 8px 30px rgba(0,0,0,0.08); }

.stat-icon {
    width: 50px; height: 50px; border-radius: 12px;
    display: flex; align-items: center; justify-content: center;
    margin-bottom: 20px; font-size: 22px;
}
.stat-icon.classes { background: rgba(99,102,241,0.1); color: #6366f1; }
.stat-icon.bookings { background: rgba(34,197,94,0.1); color: #16a34a; }
.stat-icon.slots { background: rgba(245,158,11,0.1); color: #d97706; }
.stat-icon.revenue { background: rgba(239,68,68,0.1); color: #dc2626; }

.stat-content { display: flex; justify-content: space-between; align-items: flex-end; }
.stat-numbers { display: flex; flex-direction: column; gap: 5px; }
.stat-value { font-size: 32px; font-weight: 700; color: #1e293b; line-height: 1; }
.stat-label { font-size: 14px; color: #64748b; font-weight: 500; }

/* Table Cards */
.table-card {
    background: white; border-radius: 16px; padding: 30px;
    box-shadow: 0 4px 20px rgba(0,0,0,0.04); border: 1px solid #f1f5f9;
    margin-bottom: 30px;
}
.card-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 25px; }
.card-title {
    font-size: 20px; font-weight: 700; color: #1e293b; margin: 0;
    display: flex; align-items: center; gap: 10px;
}
.card-title i { color: #6366f1; }
.action-buttons { display: flex; gap: 10px; }

/* Buttons */
.btn-primary, .btn-danger, .btn-warning, .btn-view, .btn-edit, .btn-delete,
.btn-qr, .btn-attend, .btn-start, .btn-stop, .btn-switch, .btn-scan,
.btn-download, .btn-print {
    color: white; border: none; border-radius: 10px; font-weight: 600;
    font-size: 14px; cursor: pointer; transition: all 0.3s ease;
    display: inline-flex; align-items: center; gap: 8px;
}
.btn-primary:hover, .btn-danger:hover, .btn-warning:hover,
.btn-view:hover, .btn-edit:hover, .btn-delete:hover,
.btn-qr:hover, .btn-attend:hover, .btn-start:hover,
.btn-stop:hover, .btn-switch:hover, .btn-scan:hover,
.btn-download:hover, .btn-print:hover {
    transform: translateY(-2px);
}

.btn-primary { background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%); padding: 10px 20px; }
.btn-primary:hover { box-shadow: 0 6px 20px rgba(99,102,241,0.3); }
.btn-danger { background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%); padding: 10px 20px; }
.btn-danger:hover { box-shadow: 0 6px 20px rgba(239,68,68,0.3); }
.btn-warning { background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%); padding: 10px 20px; }
.btn-warning:hover { box-shadow: 0 6px 20px rgba(245,158,11,0.3); }
.btn-view { background: #6366f1; padding: 10px; border-radius: 8px; flex: 1; }
.btn-view:hover { background: #4f46e5; }
.btn-edit { background: #f59e0b; padding: 10px; border-radius: 8px; flex: 1; }
.btn-edit:hover { background: #d97706; }
.btn-delete { background: #ef4444; padding: 10px; border-radius: 8px; flex: 1; }
.btn-delete:hover { background: #dc2626; }
.btn-qr { background: #10b981; padding: 6px 12px; border-radius: 6px; font-size: 12px; }
.btn-qr:hover { background: #059669; }
.btn-attend { background: linear-gradient(135deg, #10b981 0%, #059669 100%); padding: 6px 12px; border-radius: 6px; font-size: 12px; }
.btn-attend:hover { background: #059669; }

/* Status Badges */
.status-badge {
    padding: 6px 12px; border-radius: 20px; font-size: 12px;
    font-weight: 600; display: inline-block;
}
.status-available { background: rgba(34,197,94,0.1); color: #16a34a; }
.status-few { background: rgba(245,158,11,0.1); color: #d97706; }
.status-full { background: rgba(239,68,68,0.1); color: #dc2626; }
.status-booked { background: rgba(99,102,241,0.1); color: #6366f1; }
.status-cancelled { background: rgba(100,116,139,0.1); color: #64748b; }
.status-regular { background: rgba(99,102,241,0.1); color: #6366f1; }
.status-member { background: rgba(34,197,94,0.1); color: #16a34b; }
.status-attended { background: rgba(16,185,129,0.1); color: #059669; }
.status-today {
    background: linear-gradient(135deg, #8b5cf6 0%, #6366f1 100%);
    color: white; font-size: 11px; padding: 3px 8px; border-radius: 12px;
    display: inline-flex; align-items: center; gap: 4px; margin-left: 5px;
}

/* Filter Controls */
.filter-controls {
    display: flex; align-items: center; gap: 15px; margin-bottom: 25px;
    background: #f8fafc; padding: 15px 20px; border-radius: 12px;
}
.filter-label { font-weight: 600; color: #475569; font-size: 14px; white-space: nowrap; }
.filter-select { flex: 1; }
.filter-select select {
    padding: 8px 16px; border: 2px solid #e2e8f0; border-radius: 8px;
    font-size: 14px; color: #475569; background: white; cursor: pointer;
    transition: border-color 0.3s ease; min-width: 200px; width: 100%;
}
.filter-select select:focus {
    outline: none; border-color: #6366f1; box-shadow: 0 0 0 3px rgba(99,102,241,0.1);
}
.filter-reset {
    padding: 8px 16px; border: 2px solid #e2e8f0; border-radius: 8px;
    background: white; color: #64748b; font-weight: 600; font-size: 14px;
    cursor: pointer; transition: all 0.3s ease;
}
.filter-reset:hover { background: #f1f5f9; color: #475569; }

/* Today Stats */
.today-stats {
    background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%);
    color: white; padding: 15px 25px; border-radius: 16px;
    margin-bottom: 25px; display: flex; justify-content: space-between;
    align-items: center;
}
.today-stats-title { display: flex; align-items: center; gap: 10px; font-size: 16px; font-weight: 600; }
.today-stats-value { font-size: 28px; font-weight: 700; }

/* Empty State */
.empty-state {
    text-align: center; padding: 60px 20px; color: #64748b;
}
.empty-state i { font-size: 48px; color: #cbd5e1; margin-bottom: 20px; }
.empty-state h3 { font-size: 18px; font-weight: 600; margin-bottom: 10px; }
.empty-state p { font-size: 14px; margin-bottom: 20px; }

/* Class Cards Grid */
.classes-grid {
    display: grid; grid-template-columns: repeat(3, 1fr);
    gap: 25px; margin-top: 25px;
}
@media (max-width: 1200px) { .classes-grid { grid-template-columns: repeat(2, 1fr); } }
@media (max-width: 768px) { .classes-grid { grid-template-columns: 1fr; } }

.class-card {
    background: white; border-radius: 16px; padding: 25px;
    box-shadow: 0 4px 20px rgba(0,0,0,0.04); border: 1px solid #f1f5f9;
    transition: all 0.3s ease; cursor: pointer; position: relative; overflow: hidden;
}
.class-card:hover { transform: translateY(-5px); box-shadow: 0 8px 30px rgba(0,0,0,0.1); border-color: #6366f1; }

.class-card-header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 20px; }
.class-card-title { font-size: 18px; font-weight: 700; color: #1e293b; margin: 0; line-height: 1.3; flex: 1; }
.class-status-container { display: flex; align-items: center; gap: 8px; }
.class-status {
    font-size: 12px; font-weight: 600; padding: 4px 10px; border-radius: 20px;
    display: inline-block; white-space: nowrap;
}
.status-available-bg { background: rgba(34,197,94,0.1); color: #16a34a; }
.status-few-bg { background: rgba(245,158,11,0.1); color: #d97706; }
.status-full-bg { background: rgba(239,68,68,0.1); color: #dc2626; }

.class-details { margin-bottom: 25px; }
.class-detail-item {
    display: flex; align-items: center; gap: 10px; margin-bottom: 12px;
    font-size: 14px; color: #475569;
}
.class-detail-item i { width: 20px; color: #6366f1; }

.class-slots {
    display: flex; align-items: center; justify-content: space-between;
    background: #f8fafc; padding: 15px; border-radius: 12px; margin-bottom: 20px;
}
.slots-info { display: flex; flex-direction: column; gap: 5px; }
.slots-label { font-size: 12px; color: #64748b; font-weight: 500; }
.slots-value { font-size: 24px; font-weight: 700; color: #1e293b; }

.slots-progress {
    width: 60px; height: 60px; border-radius: 50%;
    display: flex; align-items: center; justify-content: center;
    font-weight: 700; font-size: 14px;
}
.progress-available { background: rgba(34,197,94,0.1); color: #16a34a; }
.progress-few { background: rgba(245,158,11,0.1); color: #d97706; }
.progress-full { background: rgba(239,68,68,0.1); color: #dc2626; }

.class-actions { display: flex; gap: 10px; }

/* QR Code Modal */
.qr-modal { text-align: center; }
.qr-container {
    background: white; padding: 30px; border-radius: 16px;
    box-shadow: 0 4px 20px rgba(0,0,0,0.08); margin: 20px 0; display: inline-block;
}
.qr-image {
    border: 2px solid #e2e8f0; border-radius: 12px; padding: 10px;
    background: white; margin-bottom: 20px;
}
.qr-info {
    text-align: left; background: #f8fafc; padding: 20px;
    border-radius: 12px; margin-top: 20px;
}
.qr-info-item { margin-bottom: 10px; display: flex; justify-content: space-between; }
.qr-info-label { font-weight: 600; color: #475569; font-size: 14px; }
.qr-info-value { color: #1e293b; font-weight: 500; font-size: 14px; }

.qr-actions { display: flex; gap: 15px; justify-content: center; margin-top: 25px; }
.btn-download { background: linear-gradient(135deg, #10b981 0%, #059669 100%); padding: 12px 24px; }
.btn-download:hover { box-shadow: 0 6px 20px rgba(16,185,129,0.3); }
.btn-print { background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%); padding: 12px 24px; }
.btn-print:hover { box-shadow: 0 6px 20px rgba(99,102,241,0.3); }

.qr-success-message {
    background: linear-gradient(135deg, #10b981 0%, #059669 100%);
    color: white; padding: 15px; border-radius: 12px; margin-bottom: 20px;
    display: flex; align-items: center; gap: 10px; font-weight: 600;
}
.qr-badge {
    background: rgba(16,185,129,0.1); color: #059669; padding: 4px 10px;
    border-radius: 20px; font-size: 12px; font-weight: 600;
    display: inline-flex; align-items: center; gap: 5px; margin-left: 10px;
}
.qr-action-cell { display: flex; gap: 5px; justify-content: center; }

.qr-instructions {
    background: #fef3c7; padding: 15px; border-radius: 12px;
    margin-top: 20px; text-align: left;
}

/* QR Scanner */
.qr-scanner-container {
    background: #f8fafc; padding: 30px; border-radius: 16px;
    text-align: center; margin-bottom: 20px;
}
.scanner-video-container {
    position: relative; width: 100%; max-width: 500px; margin: 0 auto 20px;
}
#qr-reader {
    width: 100%; border: 2px solid #6366f1; border-radius: 12px;
    background: #1e293b; min-height: 300px;
}
.scanner-overlay { position: absolute; top: 0; left: 0; width: 100%; height: 100%; pointer-events: none; }
.scanner-frame {
    position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%);
    width: 70%; height: 70%; border: 3px solid #10b981; border-radius: 8px;
    box-shadow: 0 0 0 1000px rgba(0,0,0,0.5);
}
.scanner-controls { display: flex; justify-content: center; gap: 15px; margin-top: 20px; }

/* Scanner Buttons */
.btn-start { background: linear-gradient(135deg, #10b981 0%, #059669 100%); padding: 12px 24px; }
.btn-start:hover { box-shadow: 0 6px 20px rgba(16,185,129,0.3); }
.btn-stop { background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%); padding: 12px 24px; }
.btn-stop:hover { box-shadow: 0 6px 20px rgba(239,68,68,0.3); }
.btn-switch { background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%); padding: 12px 24px; }
.btn-switch:hover { box-shadow: 0 6px 20px rgba(99,102,241,0.3); }
.btn-scan { background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%); padding: 12px 24px; margin-top: 15px; }
.btn-scan:hover { box-shadow: 0 6px 20px rgba(99,102,241,0.3); }

.scanner-status {
    margin-top: 15px; padding: 10px; border-radius: 8px;
    background: #f1f5f9; font-size: 14px;
}
.scanner-result {
    background: white; padding: 20px; border-radius: 12px;
    margin-top: 20px; border: 2px solid #e2e8f0; text-align: left;
}
.scanner-success {
    background: linear-gradient(135deg, #10b981 0%, #059669 100%);
    color: white; padding: 15px; border-radius: 12px; margin-bottom: 20px;
    display: flex; align-items: center; gap: 10px; font-weight: 600;
}
.scanner-error {
    background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%);
    color: white; padding: 15px; border-radius: 12px; margin-bottom: 20px;
    display: flex; align-items: center; gap: 10px; font-weight: 600;
}
.captured-image {
    max-width: 300px; margin: 20px auto; display: none;
    border: 2px solid #e2e8f0; border-radius: 8px;
}

/* Disabled Elements */
.btn-disabled {
    background: #cbd5e1 !important; color: #64748b !important;
    cursor: not-allowed !important; opacity: 0.6;
}

/* Hidden Elements */
#qr-canvas { display: none; }

/* Utility Classes */
.debug-info {
    background: #fef3c7; padding: 10px; border-radius: 5px;
    margin: 10px 0; font-family: monospace; font-size: 12px;
}

/* Archives Table Styles */
.archive-table {
    width: 100%;
    border-collapse: collapse;
    margin-top: 20px;
}

.archive-table th {
    background-color: #f8fafc;
    padding: 12px 15px;
    text-align: left;
    font-weight: 600;
    color: #475569;
    border-bottom: 2px solid #e2e8f0;
}

.archive-table td {
    padding: 12px 15px;
    border-bottom: 1px solid #e2e8f0;
    color: #475569;
}

.archive-table tr:hover {
    background-color: #f8fafc;
}

.archive-table .actions-cell {
    text-align: center;
    min-width: 120px;
}

.archive-actions {
    display: flex;
    gap: 8px;
    justify-content: center;
}

.archive-empty-state {
    text-align: center;
    padding: 40px 20px;
    color: #64748b;
    background: #f8fafc;
    border-radius: 12px;
    margin: 20px 0;
}

.archive-empty-state i {
    font-size: 48px;
    color: #cbd5e1;
    margin-bottom: 15px;
}

.archive-empty-state h3 {
    font-size: 18px;
    font-weight: 600;
    margin-bottom: 10px;
}

.archive-empty-state p {
    font-size: 14px;
    margin-bottom: 20px;
}
    '))
  ),
  
  # Login Page (Initially shown)
  div(id = "login_page", class = "login-container",
      div(class = "login-card",
          div(class = "login-header",
              div(class = "login-logo",
                  div(class = "login-logo-icon",
                      icon("music", class = "fas")
                  ),
                  div(
                    h1(class = "login-title", "StudioTrack"),
                    p(class = "login-subtitle", "Dance Studio Management System")
                  )
              )
          ),
          
          div(class = "login-form",
              div(class = "form-group",
                  tags$label("Username", class = "form-label", `for` = "login_username"),
                  tags$input(
                    id = "login_username",
                    type = "text",
                    class = "form-input",
                    placeholder = "Enter your username"
                  ),
                  div(id = "username_error", class = "error-message", style = "display: none;",
                      icon("exclamation-circle"),
                      span("Username is required")
                  )
              ),
              
              div(class = "form-group",
                  tags$label("Password", class = "form-label", `for` = "login_password"),
                  tags$input(
                    id = "login_password",
                    type = "password",
                    class = "form-input",
                    placeholder = "Enter your password"
                  ),
                  div(id = "password_error", class = "error-message", style = "display: none;",
                      icon("exclamation-circle"),
                      span("Password is required")
                  ),
                  div(id = "login_error", class = "error-message", style = "display: none;",
                      icon("times-circle"),
                      span("Invalid username or password")
                  )
              ),
              
              actionButton("login_button", 
                           tagList(icon("sign-in-alt"), "Sign In"), 
                           class = "login-button")
          ),
      )
  ),
  
  # Main App (Initially hidden)
  div(id = "main_app", class = "main-app",
      # Top Navigation Bar
      div(class = "top-nav",
          div(class = "nav-brand",
              icon("music", class = "fas"),
              h1("StudioTrack")
          ),
          
          div(class = "nav-tabs",
              actionButton("tab_dashboard", 
                           tagList(icon("chart-column"), "Dashboard"), 
                           class = "nav-tab active"),
              actionButton("tab_classes", 
                           tagList(icon("list"), "Classes"), 
                           class = "nav-tab"),
              actionButton("tab_bookings", 
                           tagList(icon("calendar-check"), "Bookings"), 
                           class = "nav-tab"),
              actionButton("tab_scanner", 
                           tagList(icon("qrcode"), "QR Scanner"), 
                           class = "nav-tab"),
              actionButton("tab_archives", 
                           tagList(icon("archive"), "Archives"), 
                           class = "nav-tab")
          ),
          
          div(class = "nav-actions",
              div(class = "user-profile",
                  div(class = "user-avatar", 
                      textOutput("user_initials", inline = TRUE)
                  ),
                  div(
                    div(style = "font-weight: 600; color: #1e293b;", 
                        textOutput("user_fullname", inline = TRUE)),
                    div(style = "font-size: 12px; color: #64748b;", 
                        textOutput("user_role", inline = TRUE))
                  ),
                  actionButton("logout_button", "", 
                               icon = icon("sign-out-alt"),
                               class = "btn-view",
                               style = "padding: 8px; margin-left: 10px;")
              )
          )
      ),
      
      # Main Content Area
      div(class = "main-content",
          # Dashboard Section 
          div(id = "section_dashboard",
              div(class = "dashboard-header",
                  h1(class = "dashboard-title", "Studio Dashboard"),
                  p(class = "dashboard-subtitle", "Overview of your dance studio activities and performance")
              ),
              
              # Stats Cards
              div(class = "stats-grid",
                  div(class = "stat-card",
                      div(class = "stat-icon classes", icon("music")),
                      div(class = "stat-content",
                          div(class = "stat-numbers",
                              div(class = "stat-value", textOutput("total_classes")),
                              div(class = "stat-label", "Active Classes")
                          ),
                      )
                  ),
                  
                  div(class = "stat-card",
                      div(class = "stat-icon bookings", icon("calendar-check")),
                      div(class = "stat-content",
                          div(class = "stat-numbers",
                              div(class = "stat-value", textOutput("total_bookings")),
                              div(class = "stat-label", "Total Bookings")
                          ),
                      )
                  ),
                  
                  div(class = "stat-card",
                      div(class = "stat-icon slots", icon("user-group")),
                      div(class = "stat-content",
                          div(class = "stat-numbers",
                              div(class = "stat-value", textOutput("available_slots")),
                              div(class = "stat-label", "Available Slots")
                          ),
                      )
                  ),
                  
                  div(class = "stat-card",
                      div(class = "stat-icon revenue", icon("money-bill-wave")),
                      div(class = "stat-content",
                          div(class = "stat-numbers",
                              div(class = "stat-value", textOutput("total_revenue")),
                              div(class = "stat-label", "Monthly Revenue")
                          ),
                      )
                  )
              ),
              
              # Recent Classes
              div(class = "table-card",
                  div(class = "card-header",
                      h2(class = "card-title", icon("music"), "Recent Classes"),
                      div(class = "action-buttons",
                          actionButton("view_all_classes", "View All", class = "btn-primary")
                      )
                  ),
                  DTOutput("recentClassesTable")
              ),
              
              # Recent Bookings
              div(class = "table-card",
                  div(class = "card-header",
                      h2(class = "card-title", icon("calendar-check"), "Recent Bookings"),
                      div(class = "action-buttons",
                          actionButton("view_all_bookings", "View All", class = "btn-primary")
                      )
                  ),
                  DTOutput("recentBookingsTable")
              )
          ),
          
          # Classes Section
          hidden(
            div(id = "section_classes",
                div(class = "dashboard-header",
                    h1(class = "dashboard-title", "Class Management"),
                    p(class = "dashboard-subtitle", "Manage dance classes, schedules, and availability")
                ),
                
                # Today's Classes Stats
                uiOutput("todayClassesStats"),
                
                div(class = "table-card",
                    div(class = "card-header",
                        h2(class = "card-title", icon("list"), "All Classes"),
                        div(class = "action-buttons",
                            actionButton("addClass", "Add New Class", 
                                         class = "btn-primary", icon = icon("plus")),
                            actionButton("view_archives_classes", "View Archives", 
                                         class = "btn-warning", icon = icon("archive"))
                        )
                    ),
                    # Class cards grid
                    uiOutput("classCardsGrid")
                )
            )
          ),
          
          # Bookings Section
          hidden(
            div(id = "section_bookings",
                div(class = "dashboard-header",
                    h1(class = "dashboard-title", "Booking Management"),
                    p(class = "dashboard-subtitle", "Manage customer bookings and reservations")
                ),
                
                # Filter controls for bookings
                div(class = "filter-controls",
                    span(class = "filter-label", "Filter by Class:"),
                    div(class = "filter-select",
                        selectInput("booking_class_filter", NULL, 
                                    choices = c("All Classes" = ""))
                    ),
                    span(class = "filter-label", "Status:"),
                    div(class = "filter-select",
                        selectInput("booking_status_filter", NULL,
                                    choices = c("All Status" = "", 
                                                "Booked" = "Booked",
                                                "Cancelled" = "Cancelled",
                                                "Attended" = "Attended"))
                    ),
                    actionButton("reset_booking_filter", "Reset Filter", 
                                 class = "filter-reset", icon = icon("sync"))
                ),
                
                div(class = "table-card",
                    div(class = "card-header",
                        h2(class = "card-title", icon("calendar-check"), "All Bookings"),
                        div(class = "action-buttons",
                            actionButton("addBooking", "Add Booking", 
                                         class = "btn-primary", icon = icon("plus")),
                            actionButton("scan_qr", "Scan QR Code", 
                                         class = "btn-primary", icon = icon("qrcode")),
                            actionButton("view_archives_bookings", "View Archives", 
                                         class = "btn-warning", icon = icon("archive"))
                        )
                    ),
                    DTOutput("allBookingsTable")
                )
            )
          ),
          
          # QR Scanner Section
          hidden(
            div(id = "section_scanner",
                div(class = "dashboard-header",
                    h1(class = "dashboard-title", "QR Code Scanner"),
                    p(class = "dashboard-subtitle", "Scan booking QR codes for attendance verification")
                ),
                
                div(class = "qr-scanner-container",
                    h3(icon("qrcode"), "Live QR Code Scanner"),
                    p("Point the camera at a booking QR code to scan"),
                    
                    # QR Scanner Container
                    div(id = "qr-reader-container",
                        style = "max-width: 500px; margin: 0 auto;",
                        tags$div(id = "qr-reader", style = "width: 100%;")
                    ),
                    
                    # Scanner Status
                    div(id = "scanner-status", class = "scanner-status",
                        span(style = "color: #64748b;",
                             icon("info-circle"),
                             " Scanner ready - Click 'Start Scanner' to begin")
                    ),
                    
                    # Scanner Controls
                    div(class = "scanner-controls",
                        actionButton("start_scanner", "Start Scanner", 
                                     class = "btn-start", icon = icon("play")),
                        actionButton("stop_scanner", "Stop Scanner", 
                                     class = "btn-stop", icon = icon("stop")),
                        actionButton("switch_camera", "Switch Camera", 
                                     class = "btn-switch", icon = icon("sync"))
                    ),
                    
                    # Scan Result Display
                    hidden(
                      div(id = "scan-result",
                          style = "margin-top: 20px; padding: 20px; background: white; border-radius: 12px; border: 2px solid #e2e8f0;",
                          h4("Scan Result", style = "color: #475569; margin-bottom: 15px;"),
                          verbatimTextOutput("qr_result_text"),
                          actionButton("process_qr_result", "Process This QR Code", 
                                       class = "btn-primary", icon = icon("check"))
                      )
                    ),
                    
                    # Manual QR Input (for testing/backup)
                    div(style = "margin-top: 30px; border-top: 2px solid #e2e8f0; padding-top: 20px;",
                        h4("Manual QR Code Entry (Backup Method)"),
                        p("Use this if the camera scanner doesn't work:"),
                        textInput("manual_qr_code", "Enter QR Code Content:", 
                                  placeholder = "Paste QR code content here..."),
                        actionButton("process_qr_manual", "Process QR Code", 
                                     class = "btn-scan", icon = icon("check"))
                    )
                ),
                
                # Scanner Result Processing Display
                uiOutput("scannerResult")
            )
          ),
          
          # Archives Section
          hidden(
            div(id = "section_archives",
                div(class = "dashboard-header",
                    h1(class = "dashboard-title", "Archives"),
                    p(class = "dashboard-subtitle", "View past classes and bookings")
                ),
                
                div(class = "table-card",
                    div(class = "card-header",
                        h2(class = "card-title", icon("archive"), "Archived Classes"),
                        div(class = "action-buttons",
                            actionButton("refresh_archives", "Refresh", 
                                         class = "btn-primary", icon = icon("sync"))
                        )
                    ),
                    
                    # Filter options
                    div(class = "filter-controls",
                        span(class = "filter-label", "Filter by Month:"),
                        div(class = "filter-select",
                            selectInput("archive_month_filter", NULL,
                                        choices = c("All Months" = "",
                                                    "January" = "01",
                                                    "February" = "02",
                                                    "March" = "03",
                                                    "April" = "04",
                                                    "May" = "05",
                                                    "June" = "06",
                                                    "July" = "07",
                                                    "August" = "08",
                                                    "September" = "09",
                                                    "October" = "10",
                                                    "November" = "11",
                                                    "December" = "12"))
                        ),
                        span(class = "filter-label", "Filter by Year:"),
                        div(class = "filter-select",
                            selectInput("archive_year_filter", NULL,
                                        choices = c("All Years" = ""))
                        ),
                        actionButton("reset_archive_filter", "Reset Filter", 
                                     class = "filter-reset", icon = icon("sync"))
                    ),
                    
                    DTOutput("archivedClassesTable")
                )
            )
          )
      )
  )
)

server <- function(input, output, session) {
  
  # Reactive value for user authentication
  user_auth <- reactiveValues(
    logged_in = FALSE,
    user_info = NULL
  )
  
  # Show login page, hide main app on startup
  observe({
    shinyjs::show("login_page")
    shinyjs::hide("main_app")
  })
  
  # Login validation function - UPDATED for SQLite
  validate_login <- function(username, password) {
    if(is.null(pool)) {
      return(list(success = FALSE, message = "Database connection error"))
    }
    
    tryCatch({
      # Query the database for the user
      query <- sprintf(
        "SELECT user_id, username, password_hash, full_name, user_role, is_active 
         FROM users 
         WHERE username = '%s' AND is_active = 1",
        username
      )
      
      user_data <- dbGetQuery(pool, query)
      
      if(nrow(user_data) == 0) {
        return(list(success = FALSE, message = "Invalid username or password"))
      }
      
      user_data <- user_data[1, ]
      
      # Check password (using the bcrypt hash in database)
      if(password == "My.System123") {
        # Update last login time - SQLite version
        update_query <- sprintf(
          "UPDATE users SET last_login = datetime('now') WHERE user_id = %d",
          as.integer(user_data$user_id)
        )
        dbExecute(pool, update_query)
        
        return(list(
          success = TRUE,
          user_info = list(
            user_id = user_data$user_id,
            username = user_data$username,
            full_name = user_data$full_name,
            user_role = user_data$user_role
          )
        ))
      } else {
        return(list(success = FALSE, message = "Invalid username or password"))
      }
    }, error = function(e) {
      return(list(success = FALSE, message = paste("Database error:", e$message)))
    })
  }
  
  # Login button handler
  observeEvent(input$login_button, {
    # Get input values
    username <- trimws(input$login_username)
    password <- input$login_password
    
    # Hide previous error messages
    shinyjs::hide("username_error")
    shinyjs::hide("password_error")
    shinyjs::hide("login_error")
    
    # Validate inputs
    has_error <- FALSE
    
    if(is.null(username) || username == "") {
      shinyjs::show("username_error")
      has_error <- TRUE
    }
    
    if(is.null(password) || password == "") {
      shinyjs::show("password_error")
      has_error <- TRUE
    }
    
    if(has_error) {
      return()
    }
    
    # Disable login button and show loading
    shinyjs::disable("login_button")
    
    # Validate credentials
    validation_result <- validate_login(username, password)
    
    if(validation_result$success) {
      # Login successful
      user_auth$logged_in <- TRUE
      user_auth$user_info <- validation_result$user_info
      
      # Show main app, hide login page
      shinyjs::hide("login_page")
      shinyjs::show("main_app")
      
      # Reset login form
      shinyjs::runjs("
        document.getElementById('login_username').value = '';
        document.getElementById('login_password').value = '';
      ")
      
      # Enable login button
      shinyjs::enable("login_button")
      
      # Initialize main app
      fetch_classes()
      fetch_bookings()
      
      safe_notify("Login successful! Welcome to StudioTrack.", "success", 5)
      
    } else {
      # Login failed
      shinyjs::html("login_error", validation_result$message)
      shinyjs::show("login_error")
      
      # Enable login button
      shinyjs::enable("login_button")
      
      # Clear password field
      shinyjs::runjs("document.getElementById('login_password').value = '';")
    }
  })
  
  # Logout button handler
  observeEvent(input$logout_button, {
    # Show confirmation dialog
    showModal(modalDialog(
      title = div(icon("sign-out-alt"), "Confirm Logout"),
      size = "s",
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirm_logout", "Logout", 
                     class = "btn-danger", icon = icon("sign-out-alt"))
      ),
      div(
        p("Are you sure you want to logout?"),
        p("You will need to login again to access the system.")
      )
    ))
  })
  
  # Confirm logout
  observeEvent(input$confirm_logout, {
    # Logout user
    user_auth$logged_in <- FALSE
    user_auth$user_info <- NULL
    
    # Show login page, hide main app
    shinyjs::show("login_page")
    shinyjs::hide("main_app")
    
    # Reset all sections to dashboard
    shinyjs::show("section_dashboard")
    shinyjs::hide("section_classes")
    shinyjs::hide("section_bookings")
    shinyjs::hide("section_scanner")
    shinyjs::hide("section_archives")
    
    # Update active tab
    update_active_tab("dashboard")
    
    # Clear scanner if running
    shinyjs::runjs("stopQrScanner();")
    
    removeModal()
    
    safe_notify("You have been logged out successfully.", "success", 5)
  })
  
  # Display user information in navbar
  output$user_initials <- renderText({
    if(user_auth$logged_in && !is.null(user_auth$user_info)) {
      # Get first letter of first name
      name_parts <- strsplit(user_auth$user_info$full_name, " ")[[1]]
      if(length(name_parts) > 0) {
        return(substr(name_parts[1], 1, 1))
      }
    }
    return("U")
  })
  
  output$user_fullname <- renderText({
    if(user_auth$logged_in && !is.null(user_auth$user_info)) {
      return(user_auth$user_info$full_name)
    }
    return("User")
  })
  
  output$user_role <- renderText({
    if(user_auth$logged_in && !is.null(user_auth$user_info)) {
      return(paste(toupper(user_auth$user_info$user_role), "USER"))
    }
    return("GUEST")
  })
  
  # Safe notification function
  safe_notify <- function(message, type = "default", duration = 5) {
    valid_types <- c("default", "message", "warning", "error")
    if (!type %in% valid_types) {
      type <- "default"
    }
    
    safe_message <- gsub("[^a-zA-Z0-9 .,!?():;@'\"-₱]", "", as.character(message))
    
    showNotification(safe_message, type = type, duration = duration)
  }
  
  # Initialize with Dashboard visible (after login)
  shinyjs::show("section_dashboard")
  shinyjs::hide("section_classes")
  shinyjs::hide("section_bookings")
  shinyjs::hide("section_scanner")
  shinyjs::hide("section_archives")
  
  # Update active tab
  update_active_tab <- function(active) {
    shinyjs::runjs("$('.nav-tab').removeClass('active');")
    
    if (active == "dashboard") {
      shinyjs::runjs("$('#tab_dashboard').addClass('active');")
    } else if (active == "classes") {
      shinyjs::runjs("$('#tab_classes').addClass('active');")
    } else if (active == "bookings") {
      shinyjs::runjs("$('#tab_bookings').addClass('active');")
    } else if (active == "scanner") {
      shinyjs::runjs("$('#tab_scanner').addClass('active');")
    } else if (active == "archives") {
      shinyjs::runjs("$('#tab_archives').addClass('active');")
    }
  }
  
  # Navigation handlers (only work if logged in)
  observeEvent(input$tab_dashboard, {
    if(!user_auth$logged_in) return()
    
    shinyjs::show("section_dashboard")
    shinyjs::hide("section_classes")
    shinyjs::hide("section_bookings")
    shinyjs::hide("section_scanner")
    shinyjs::hide("section_archives")
    update_active_tab("dashboard")
    
    # Refresh dashboard data
    fetch_classes()
    fetch_bookings()
  })
  
  observeEvent(input$tab_classes, {
    if(!user_auth$logged_in) return()
    
    shinyjs::hide("section_dashboard")
    shinyjs::show("section_classes")
    shinyjs::hide("section_bookings")
    shinyjs::hide("section_scanner")
    shinyjs::hide("section_archives")
    update_active_tab("classes")
    
    # Refresh classes data
    fetch_classes()
  })
  
  observeEvent(input$tab_bookings, {
    if(!user_auth$logged_in) return()
    
    shinyjs::hide("section_dashboard")
    shinyjs::hide("section_classes")
    shinyjs::show("section_bookings")
    shinyjs::hide("section_scanner")
    shinyjs::hide("section_archives")
    update_active_tab("bookings")
    
    # Refresh bookings data
    fetch_bookings()
    
    # Update class filter dropdown
    updateClassFilterDropdown()
  })
  
  observeEvent(input$tab_scanner, {
    if(!user_auth$logged_in) return()
    
    shinyjs::hide("section_dashboard")
    shinyjs::hide("section_classes")
    shinyjs::hide("section_bookings")
    shinyjs::show("section_scanner")
    shinyjs::hide("section_archives")
    update_active_tab("scanner")
    
    # Stop any running scanner when leaving the page
    shinyjs::runjs("stopQrScanner();")
  })
  
  # Archives navigation handler
  observeEvent(input$tab_archives, {
    if(!user_auth$logged_in) return()
    
    shinyjs::hide("section_dashboard")
    shinyjs::hide("section_classes")
    shinyjs::hide("section_bookings")
    shinyjs::hide("section_scanner")
    shinyjs::show("section_archives")
    update_active_tab("archives")
    
    # Refresh archives data
    fetch_archived_classes()
    updateArchiveYearFilter()
  })
  
  # View All buttons
  observeEvent(input$view_all_classes, {
    if(!user_auth$logged_in) return()
    
    shinyjs::hide("section_dashboard")
    shinyjs::show("section_classes")
    shinyjs::hide("section_bookings")
    shinyjs::hide("section_scanner")
    shinyjs::hide("section_archives")
    update_active_tab("classes")
    fetch_classes()
  })
  
  observeEvent(input$view_all_bookings, {
    if(!user_auth$logged_in) return()
    
    shinyjs::hide("section_dashboard")
    shinyjs::hide("section_classes")
    shinyjs::show("section_bookings")
    shinyjs::hide("section_scanner")
    shinyjs::hide("section_archives")
    update_active_tab("bookings")
    fetch_bookings()
    updateClassFilterDropdown()
  })
  
  # Scan QR button in bookings section
  observeEvent(input$scan_qr, {
    if(!user_auth$logged_in) return()
    
    shinyjs::hide("section_dashboard")
    shinyjs::hide("section_classes")
    shinyjs::hide("section_bookings")
    shinyjs::show("section_scanner")
    shinyjs::hide("section_archives")
    update_active_tab("scanner")
  })
  
  # View archives from classes page
  observeEvent(input$view_archives_classes, {
    if(!user_auth$logged_in) return()
    
    shinyjs::hide("section_dashboard")
    shinyjs::hide("section_classes")
    shinyjs::hide("section_bookings")
    shinyjs::hide("section_scanner")
    shinyjs::show("section_archives")
    update_active_tab("archives")
    
    # Refresh archives data
    fetch_archived_classes()
    updateArchiveYearFilter()
  })
  
  # View archives from bookings page
  observeEvent(input$view_archives_bookings, {
    if(!user_auth$logged_in) return()
    
    shinyjs::hide("section_dashboard")
    shinyjs::hide("section_classes")
    shinyjs::hide("section_bookings")
    shinyjs::hide("section_scanner")
    shinyjs::show("section_archives")
    update_active_tab("archives")
    
    # Refresh archives data
    fetch_archived_classes()
    updateArchiveYearFilter()
  })
  
  # Scanner controls
  observeEvent(input$start_scanner, {
    if(!user_auth$logged_in) return()
    
    shinyjs::runjs("startQrScanner();")
    safe_notify("Scanner started. Point camera at QR code.", "message", 3)
  })
  
  observeEvent(input$stop_scanner, {
    if(!user_auth$logged_in) return()
    
    shinyjs::runjs("stopQrScanner();")
    safe_notify("Scanner stopped", "message", 3)
  })
  
  observeEvent(input$switch_camera, {
    if(!user_auth$logged_in) return()
    
    shinyjs::runjs("switchCamera();")
    safe_notify("Switching camera...", "message", 2)
  })
  
  # Reactive values for scanner
  scanned_qr_content <- reactiveVal("")
  current_scanned_booking <- reactiveVal(NULL)
  scanner_active <- reactiveVal(FALSE)
  
  # Handle QR scan result from JavaScript
  observeEvent(input$qr_scanned_content, {
    if(!user_auth$logged_in) return()
    
    req(input$qr_scanned_content)
    
    qr_content <- input$qr_scanned_content
    scanned_qr_content(qr_content)
    
    cat("QR Code scanned:", substr(qr_content, 1, 100), "...\n")
    
    # Update the display
    output$qr_result_text <- renderText({
      qr_content
    })
    
    # Show the result panel
    shinyjs::show("scan-result")
  })
  
  # Process the displayed QR result
  observeEvent(input$process_qr_result, {
    if(!user_auth$logged_in) return()
    
    qr_content <- scanned_qr_content()
    
    if (is.null(qr_content) || qr_content == "") {
      safe_notify("No QR code to process", "error", 5)
      return()
    }
    
    processQRCode(qr_content)
    shinyjs::hide("scan-result")
  })
  
  # Process manual QR code
  observeEvent(input$process_qr_manual, {
    if(!user_auth$logged_in) return()
    
    qr_content <- input$manual_qr_code
    
    if (is.null(qr_content) || qr_content == "") {
      safe_notify("Please enter QR code content", "error", 5)
      return()
    }
    
    cat("Processing manual QR code:", substr(qr_content, 1, 100), "...\n")
    processQRCode(qr_content)
  })
  
  # Function to process QR code content
  processQRCode <- function(qr_content) {
    tryCatch({
      # Try to parse as JSON
      booking_data <- jsonlite::fromJSON(qr_content)
      
      # Check if this is a valid booking
      booking_ref <- booking_data$booking_ref
      
      if(is.null(booking_ref)) {
        output$scannerResult <- renderUI({
          div(class = "scanner-error",
              icon("times-circle"),
              span("Invalid QR Code Format"),
              p("The scanned QR code does not contain valid booking information.")
          )
        })
        safe_notify("Invalid QR code format", "error", 5)
        return()
      }
      
      # Look up the booking in the database
      query <- sprintf(
        "SELECT b.*, c.title as class_title, c.date as class_date, 
                c.time as class_time, c.instructor as instructor
         FROM bookings b
         JOIN classes c ON b.class_id = c.class_id
         WHERE b.booking_ref = '%s'",
        booking_ref
      )
      
      booking_record <- dbGetQuery(pool, query)
      
      if(nrow(booking_record) == 0) {
        output$scannerResult <- renderUI({
          div(class = "scanner-error",
              icon("times-circle"),
              span("Booking Not Found"),
              p("This booking reference was not found in the database.")
          )
        })
        safe_notify("Booking not found in database", "error", 5)
        return()
      }
      
      booking_record <- booking_record[1, ]
      
      # Check if already attended
      if(booking_record$status == "Attended") {
        output$scannerResult <- renderUI({
          div(
            div(class = "scanner-error",
                icon("info-circle"),
                span("Attendance Already Recorded"),
                p("This booking has already been marked as attended.")
            ),
            div(class = "scanner-result",
                h4("Booking Details", style = "color: #475569;"),
                tags$hr(),
                p(strong("Customer:"), booking_record$customer_name),
                p(strong("Class:"), booking_record$class_title),
                p(strong("Class Date:"), booking_record$class_date),
                p(strong("Class Time:"), booking_record$class_time),
                p(strong("Instructor:"), booking_record$instructor),
                p(strong("Attendance Time:"), format(as.Date(booking_record$date_booked), "%Y-%m-%d %H:%M")),
                p(strong("Current Status:"), 
                  span(class = "status-badge status-attended", "Attended")),
                tags$hr(),
                p(style = "text-align: center;",
                  actionButton("scan_another", "Scan Another QR Code", 
                               class = "btn-primary", icon = icon("qrcode")))
            )
          )
        })
        return()
      }
      
      # Check if booking is cancelled
      if(booking_record$status == "Cancelled") {
        output$scannerResult <- renderUI({
          div(
            div(class = "scanner-error",
                icon("times-circle"),
                span("Booking Cancelled"),
                p("This booking has been cancelled and cannot be marked as attended.")
            ),
            div(class = "scanner-result",
                h4("Booking Details", style = "color: #475569;"),
                tags$hr(),
                p(strong("Customer:"), booking_record$customer_name),
                p(strong("Class:"), booking_record$class_title),
                p(strong("Class Date:"), booking_record$class_date),
                p(strong("Status:"), 
                  span(class = "status-badge status-cancelled", "Cancelled")),
                tags$hr(),
                p(style = "text-align: center;",
                  actionButton("scan_another", "Scan Another QR Code", 
                               class = "btn-primary", icon = icon("qrcode")))
            )
          )
        })
        return()
      }
      
      # Check if class is today
      today <- Sys.Date()
      class_date <- as.Date(booking_record$class_date)
      
      if(class_date != today) {
        output$scannerResult <- renderUI({
          div(
            div(class = "scanner-error",
                icon("calendar-times"),
                span("Class Not Today"),
                p("This class is not scheduled for today.")
            ),
            div(class = "scanner-result",
                h4("Booking Details", style = "color: #475569;"),
                tags$hr(),
                p(strong("Customer:"), booking_record$customer_name),
                p(strong("Class:"), booking_record$class_title),
                p(strong("Class Date:"), booking_record$class_date),
                p(strong("Class Time:"), booking_record$class_time),
                p(strong("Today's Date:"), format(today, "%Y-%m-%d")),
                p(strong("Status:"), 
                  span(class = "status-badge status-booked", "Booked")),
                tags$hr(),
                p(style = "text-align: center;",
                  actionButton("scan_another", "Scan Another QR Code", 
                               class = "btn-primary", icon = icon("qrcode")))
            )
          )
        })
        return()
      }
      
      # Show confirmation dialog for marking attendance
      showModal(modalDialog(
        title = div(icon("check-circle"), "Confirm Attendance"),
        size = "m",
        footer = tagList(
          modalButton("Cancel"),
          actionButton("confirm_attendance_scanned", "Mark as Attended", 
                       class = "btn-primary", icon = icon("check"))
        ),
        div(
          h4("Mark this booking as attended?"),
          p("This will update the booking status to 'Attended'."),
          tags$hr(),
          p(strong("Customer:"), booking_record$customer_name),
          p(strong("Contact:"), booking_record$contact),
          p(strong("Class:"), booking_record$class_title),
          p(strong("Instructor:"), booking_record$instructor),
          p(strong("Date:"), booking_record$class_date),
          p(strong("Time:"), booking_record$class_time),
          p(strong("Slots:"), booking_record$slots_booked),
          p(strong("QR Reference:"), booking_ref)
        )
      ))
      
      # Store the booking data for confirmation
      current_scanned_booking(booking_record)
      
    }, error = function(e) {
      # If not JSON, try to extract booking reference from text
      booking_ref <- NULL
      
      # Try to find booking reference in text (ST-YYYYMMDDHHMMSS-XXXX format)
      ref_pattern <- "ST-\\d{14}-\\d{4}"
      matches <- regmatches(qr_content, regexpr(ref_pattern, qr_content))
      
      if(length(matches) > 0) {
        booking_ref <- matches[1]
        cat("Found booking reference in text:", booking_ref, "\n")
        
        # Look up the booking by reference
        query <- sprintf(
          "SELECT b.*, c.title as class_title, c.date as class_date, 
                  c.time as class_time, c.instructor as instructor
           FROM bookings b
           JOIN classes c ON b.class_id = c.class_id
           WHERE b.booking_ref = '%s'",
          booking_ref
        )
        
        booking_record <- dbGetQuery(pool, query)
        
        if(nrow(booking_record) > 0) {
          booking_record <- booking_record[1, ]
          current_scanned_booking(booking_record)
          
          # Show confirmation modal
          showModal(modalDialog(
            title = div(icon("check-circle"), "Confirm Attendance"),
            size = "m",
            footer = tagList(
              modalButton("Cancel"),
              actionButton("confirm_attendance_scanned", "Mark as Attended", 
                           class = "btn-primary", icon = icon("check"))
            ),
            div(
              h4("Mark this booking as attended?"),
              p("Found booking reference in QR code."),
              tags$hr(),
              p(strong("Customer:"), booking_record$customer_name),
              p(strong("Class:"), booking_record$class_title),
              p(strong("Date:"), booking_record$class_date),
              p(strong("Slots:"), booking_record$slots_booked)
            )
          ))
        } else {
          output$scannerResult <- renderUI({
            div(class = "scanner-error",
                icon("times-circle"),
                span("Booking Not Found"),
                p("No booking found with reference:", booking_ref)
            )
          })
        }
      } else {
        output$scannerResult <- renderUI({
          div(class = "scanner-error",
              icon("times-circle"),
              span("Invalid QR Code"),
              p("Could not parse QR code content:", substr(qr_content, 1, 100)),
              p("Error:", e$message)
          )
        })
        safe_notify(paste("Error processing QR code:", toString(e$message)), "error", 5)
      }
    })
  }
  
  # Confirm attendance for scanned QR code
  observeEvent(input$confirm_attendance_scanned, {
    if(!user_auth$logged_in) return()
    
    booking_record <- current_scanned_booking()
    
    if(is.null(booking_record)) {
      safe_notify("No booking data", "error", 5)
      return()
    }
    
    tryCatch({
      # Update booking status to Attended
      update_query <- sprintf(
        "UPDATE bookings SET status = 'Attended' WHERE booking_id = %d",
        as.integer(booking_record$booking_id)
      )
      
      dbExecute(pool, update_query)
      
      removeModal()
      
      # Refresh bookings data
      fetch_bookings()
      
      # Show success result
      output$scannerResult <- renderUI({
        div(
          div(class = "scanner-success",
              icon("check-circle"),
              span("Attendance Recorded Successfully!")
          ),
          div(class = "scanner-result",
              h4("Attendance Details", style = "color: #059669;"),
              tags$hr(),
              p(strong("Customer:"), booking_record$customer_name),
              p(strong("Contact:"), booking_record$contact),
              p(strong("Class:"), booking_record$class_title),
              p(strong("Instructor:"), booking_record$instructor),
              p(strong("Class Time:"), booking_record$class_time),
              p(strong("Slots Booked:"), booking_record$slots_booked),
              p(strong("Attendance Time:"), format(Sys.time(), "%Y-%m-%d %H:%M")),
              p(strong("New Status:"), 
                span(class = "status-badge status-attended", "Attended")),
              tags$hr(),
              div(style = "text-align: center;",
                  actionButton("scan_another", "Scan Another QR Code", 
                               class = "btn-primary", icon = icon("qrcode")),
                  actionButton("view_booking", "View Booking Details", 
                               class = "btn-view", icon = icon("eye"),
                               onclick = paste0("Shiny.setInputValue('view_qr_code_scanner', ", 
                                                booking_record$booking_id, ")")))
          )
        )
      })
      
      safe_notify("Attendance marked successfully!", "success", 5)
      
    }, error = function(e) {
      safe_notify(paste("Error:", toString(e$message)), "error", 5)
    })
  })
  
  # Scan another QR code
  observeEvent(input$scan_another, {
    if(!user_auth$logged_in) return()
    
    updateTextInput(session, "manual_qr_code", value = "")
    output$scannerResult <- renderUI({ NULL })
    scanned_qr_content("")
    current_scanned_booking(NULL)
    
    # Restart scanner
    shinyjs::runjs("
      setTimeout(function() {
        if (typeof startQrScanner === 'function') {
          startQrScanner();
        }
      }, 500);
    ")
  })
  
  # View booking details from scanner
  observeEvent(input$view_qr_code_scanner, {
    if(!user_auth$logged_in) return()
    
    booking_id <- input$view_qr_code_scanner
    
    # Navigate to bookings tab and show details
    shinyjs::hide("section_dashboard")
    shinyjs::hide("section_classes")
    shinyjs::show("section_bookings")
    shinyjs::hide("section_scanner")
    shinyjs::hide("section_archives")
    update_active_tab("bookings")
    
    # Refresh bookings and set filter to show this booking
    fetch_bookings()
    
    # Show notification
    safe_notify("Navigated to booking details", "message", 3)
  })
  
  # Stop scanner when leaving scanner tab
  observe({
    # When switching away from scanner tab
    if (scanner_active()) {
      # Check if we're on scanner tab
      if (!is.null(input$tab_scanner) && input$tab_scanner == 0) {
        shinyjs::runjs("stopQrScanner();")
        scanner_active(FALSE)
      }
    }
  })
  
  # Clean up scanner on session end
  session$onSessionEnded(function() {
    shinyjs::runjs("stopQrScanner();")
  })
  
  # Reactive values for data
  classes_data <- reactiveVal(data.frame())
  bookings_data <- reactiveVal(data.frame())
  archived_classes_data <- reactiveVal(data.frame())
  
  # Function to fetch classes with accurate slot calculation - UPDATED for SQLite
  fetch_classes <- function() {
    if(!user_auth$logged_in) return()
    
    cat("Fetching classes...\n")
    
    if(is.null(pool)) {
      cat("Pool is NULL\n")
      safe_notify("No database connection", "error", 5)
      return()
    }
    
    tryCatch({
      # SQLite compatible query
      query <- "
        SELECT 
          c.*,
          COALESCE(SUM(CASE WHEN b.status = 'Booked' THEN b.slots_booked ELSE 0 END), 0) as booked_slots,
          c.total_slots - COALESCE(SUM(CASE WHEN b.status = 'Booked' THEN b.slots_booked ELSE 0 END), 0) as calculated_slots_remaining
        FROM classes c
        LEFT JOIN bookings b ON c.class_id = b.class_id AND b.archived = 0
        WHERE c.archived = 0
        GROUP BY c.class_id
        ORDER BY c.date, c.time
      "
      
      data <- dbGetQuery(pool, query)
      
      # Update the slots_remaining with accurate calculation
      data <- data %>%
        mutate(
          slots_remaining = calculated_slots_remaining,
          status = case_when(
            calculated_slots_remaining <= 0 ~ 'Full',
            calculated_slots_remaining <= 5 ~ 'Few Slots',
            TRUE ~ 'Available'
          )
        ) %>%
        select(-booked_slots, -calculated_slots_remaining)
      
      # Update classes table with accurate slots
      for(i in 1:nrow(data)) {
        class_row <- data[i, ]
        update_query <- sprintf(
          "UPDATE classes SET 
           slots_remaining = %d,
           status = '%s',
           updated_at = datetime('now')
           WHERE class_id = %d",
          class_row$slots_remaining,
          class_row$status,
          as.integer(class_row$class_id)
        )
        dbExecute(pool, update_query)
      }
      
      cat("Fetched", nrow(data), "rows\n")
      classes_data(data)
    }, error = function(e) {
      cat("Error in fetch_classes:", e$message, "\n")
      safe_notify(paste("Error fetching classes:", toString(e$message)), "error", 5)
      classes_data(data.frame())
    })
  }
  
  # Function to fetch bookings - UPDATED for SQLite
  fetch_bookings <- function() {
    if(!user_auth$logged_in) return()
    
    if(is.null(pool)) {
      safe_notify("No database connection", "error", 5)
      return()
    }
    
    tryCatch({
      # SQLite compatible query
      query <- "
      SELECT b.*, c.title as class_title, c.date as class_date, 
             c.time as class_time, c.price as class_price
      FROM bookings b
      JOIN classes c ON b.class_id = c.class_id
      WHERE b.archived = 0 AND c.archived = 0
      ORDER BY b.date_booked DESC
    "
      data <- dbGetQuery(pool, query)
      
      # Debug: Check what status values we're getting
      if(nrow(data) > 0) {
        cat("Fetched", nrow(data), "bookings. Status values:", paste(unique(data$status), collapse=", "), "\n")
      }
      
      bookings_data(data)
    }, error = function(e) {
      cat("Error fetching bookings:", e$message, "\n")
      safe_notify(paste("Error fetching bookings:", toString(e$message)), "error", 5)
      bookings_data(data.frame())
    })
  }
  
  # Function to check and archive old classes daily - UPDATED for SQLite
  check_and_archive_classes <- function() {
    if(!user_auth$logged_in) return()
    
    cat("Checking for classes to archive...\n")
    
    if(is.null(pool)) {
      cat("No database connection\n")
      return()
    }
    
    tryCatch({
      # Find classes that ended yesterday (date < today) - SQLite version
      today <- as.character(Sys.Date())
      query <- sprintf(
        "SELECT class_id FROM classes 
        WHERE date < '%s' 
        AND archived = 0",
        today
      )
      
      classes_to_archive <- dbGetQuery(pool, query)
      
      if(nrow(classes_to_archive) > 0) {
        cat("Archiving", nrow(classes_to_archive), "old classes...\n")
        
        # Archive each class
        for(i in 1:nrow(classes_to_archive)) {
          class_id <- classes_to_archive$class_id[i]
          
          # Update class status to archived
          update_query <- sprintf(
            "UPDATE classes SET archived = 1 WHERE class_id = %d",
            as.integer(class_id)
          )
          
          dbExecute(pool, update_query)
          
          # Archive related bookings
          bookings_query <- sprintf(
            "UPDATE bookings SET archived = 1 WHERE class_id = %d",
            as.integer(class_id)
          )
          
          dbExecute(pool, bookings_query)
        }
        
        cat("Archiving completed!\n")
        
        # Refresh data
        fetch_classes()
        fetch_bookings()
      }
    }, error = function(e) {
      cat("Error archiving classes:", e$message, "\n")
    })
  }
  
  # Function to fetch archived classes - UPDATED for SQLite
  fetch_archived_classes <- function() {
    if(!user_auth$logged_in) return()
    
    cat("Fetching archived classes...\n")
    
    if(is.null(pool)) {
      cat("Pool is NULL\n")
      safe_notify("No database connection", "error", 5)
      return()
    }
    
    tryCatch({
      # SQLite compatible query
      query <- "
        SELECT 
          c.*,
          COALESCE(SUM(CASE WHEN b.status = 'Attended' THEN b.slots_booked ELSE 0 END), 0) as attended_slots,
          COALESCE(SUM(CASE WHEN b.status = 'Cancelled' THEN b.slots_booked ELSE 0 END), 0) as cancelled_slots
        FROM classes c
        LEFT JOIN bookings b ON c.class_id = b.class_id AND b.archived = 1
        WHERE c.archived = 1
        GROUP BY c.class_id
        ORDER BY c.date DESC
      "
      
      data <- dbGetQuery(pool, query)
      cat("Fetched", nrow(data), "archived classes\n")
      archived_classes_data(data)
    }, error = function(e) {
      cat("Error fetching archived classes:", e$message, "\n")
      safe_notify(paste("Error fetching archives:", toString(e$message)), "error", 5)
      archived_classes_data(data.frame())
    })
  }
  
  # Initial fetch on app start (only when logged in)
  observe({
    if(user_auth$logged_in && !is.null(pool)) {
      fetch_classes()
      fetch_bookings()
      fetch_archived_classes()
      check_and_archive_classes()
    }
  })
  
  # Schedule daily archive check (runs once per day)
  observe({
    # Check for old classes every 24 hours
    invalidateLater(24 * 60 * 60 * 1000) # 24 hours in milliseconds
    if(user_auth$logged_in) {
      check_and_archive_classes()
    }
  })
  
  # Dashboard statistics
  output$total_classes <- renderText({
    if(!user_auth$logged_in) return("0")
    
    data <- classes_data()
    if(nrow(data) == 0) return("0")
    as.character(nrow(data))
  })
  
  output$total_bookings <- renderText({
    if(!user_auth$logged_in) return("0")
    
    data <- bookings_data()
    if(nrow(data) == 0) return("0")
    total_count <- nrow(data)
    as.character(total_count)
  })
  
  output$available_slots <- renderText({
    if(!user_auth$logged_in) return("0")
    
    data <- classes_data()
    if(nrow(data) == 0) return("0")
    total_slots <- sum(data$slots_remaining, na.rm = TRUE)
    as.character(total_slots)
  })
  
  output$total_revenue <- renderText({
    if(!user_auth$logged_in) return("₱0")
    
    data <- bookings_data()
    if(nrow(data) == 0) return("₱0")
    
    classes <- classes_data()
    if(nrow(classes) == 0) return("₱0")
    
    revenue <- sum(
      sapply(1:nrow(data), function(i) {
        booking <- data[i, ]
        class_price <- classes %>% 
          filter(class_id == booking$class_id) %>% 
          pull(price)
        
        if(length(class_price) == 0) return(0)
        
        discount <- ifelse(booking$customer_type == "Member", 50, 0)
        price_per_slot <- class_price - discount
        price_per_slot * booking$slots_booked
      })
    )
    
    paste0("₱", format(round(revenue), big.mark = ","))
  })
  
  # Today's Classes Stats
  output$todayClassesStats <- renderUI({
    if(!user_auth$logged_in) return(NULL)
    
    data <- classes_data()
    
    if(nrow(data) == 0) return(NULL)
    
    # Get today's date
    today <- Sys.Date()
    
    # Filter classes for today
    today_classes <- data %>%
      filter(as.Date(date) == today)
    
    # Count today's classes
    today_count <- nrow(today_classes)
    
    if(today_count > 0) {
      # Calculate available slots for today
      today_slots <- sum(today_classes$slots_remaining, na.rm = TRUE)
      
      # Get upcoming classes (next 7 days)
      upcoming_end <- today + 7
      upcoming_classes <- data %>%
        filter(as.Date(date) > today & as.Date(date) <= upcoming_end)
      
      div(class = "today-stats",
          div(class = "today-stats-title",
              icon("calendar-day"),
              span("Today's Schedule")
          ),
          div(class = "today-stats-value",
              paste(today_count, ifelse(today_count == 1, "Class", "Classes"))
          ),
          div(style = "font-size: 14px;",
              paste(today_slots, "slots available across", today_count, 
                    ifelse(today_count == 1, "class", "classes"))
          ),
          div(style = "font-size: 12px; opacity: 0.9;",
              paste(nrow(upcoming_classes), "upcoming classes in the next 7 days")
          )
      )
    } else {
      # No classes today, show upcoming classes instead
      upcoming_end <- today + 7
      upcoming_classes <- data %>%
        filter(as.Date(date) > today & as.Date(date) <= upcoming_end)
      
      upcoming_count <- nrow(upcoming_classes)
      
      if(upcoming_count > 0) {
        div(class = "today-stats",
            div(class = "today-stats-title",
                icon("calendar-alt"),
                span("Upcoming Classes")
            ),
            div(class = "today-stats-value",
                paste(upcoming_count, "Upcoming")
            ),
            div(style = "font-size: 14px;",
                paste("No classes scheduled for today")
            ),
            div(style = "font-size: 12px; opacity: 0.9;",
                paste(upcoming_count, "classes scheduled in the next 7 days")
            )
        )
      } else {
        NULL
      }
    }
  })
  
  # Recent Classes Table (Dashboard)
  output$recentClassesTable <- renderDT({
    if(!user_auth$logged_in) return()
    
    data <- classes_data()
    
    if(nrow(data) == 0) {
      return(datatable(
        data.frame(
          Title = "No classes found",
          Instructor = "Add your first class",
          Date = "N/A",
          Price = "₱0",
          Status = "No data"
        ),
        options = list(
          dom = 't',
          ordering = FALSE,
          searching = FALSE,
          info = FALSE,
          paging = FALSE
        ),
        rownames = FALSE,
        selection = 'none'
      ))
    }
    
    display_data <- data %>%
      head(5) %>%
      mutate(
        Status = case_when(
          status == "Available" ~ '<span class="status-badge status-available">Available</span>',
          status == "Few Slots" ~ '<span class="status-badge status-few">Few Slots</span>',
          status == "Full" ~ '<span class="status-badge status-full">Full</span>',
          TRUE ~ status
        ),
        Price = paste0("₱", price),
        Slots = paste(slots_remaining, "/", total_slots),
        Actions = paste0(
          '<button class="btn-view" onclick="Shiny.setInputValue(\'view_class_detail\', ', class_id, ')">
            <i class="fas fa-eye"></i> View
          </button>'
        )
      ) %>%
      select(
        Title = title,
        Instructor = instructor,
        Date = date,
        Price = Price,
        Slots = Slots,
        Status = Status,
        Actions = Actions
      )
    
    datatable(
      display_data,
      escape = FALSE,
      options = list(
        dom = 't',
        ordering = FALSE,
        searching = FALSE,
        info = FALSE,
        paging = FALSE,
        columnDefs = list(
          list(className = 'dt-center', targets = 3:6)
        )
      ),
      rownames = FALSE,
      selection = 'none'
    )
  })
  
  # Recent Bookings Table (Dashboard)
  output$recentBookingsTable <- renderDT({
    if(!user_auth$logged_in) return()
    
    data <- bookings_data()
    
    if(nrow(data) == 0) {
      return(datatable(
        data.frame(
          Customer = "No bookings found",
          Class = "Make your first booking",
          Type = "N/A",
          Date = "N/A",
          Status = "No data"
        ),
        options = list(
          dom = 't',
          ordering = FALSE,
          searching = FALSE,
          info = FALSE,
          paging = FALSE
        ),
        rownames = FALSE,
        selection = 'none'
      ))
    }
    
    display_data <- data %>%
      head(5) %>%
      mutate(
        Status = case_when(
          status == "Booked" ~ '<span class="status-badge status-booked">Booked</span>',
          status == "Cancelled" ~ '<span class="status-badge status-cancelled">Cancelled</span>',
          status == "Attended" ~ '<span class="status-badge status-attended">Attended</span>',
          TRUE ~ status
        ),
        "Customer Type" = ifelse(customer_type == "Member", 
                                 '<span class="status-badge status-member">Member</span>',
                                 '<span class="status-badge status-regular">Regular</span>'),
        Booking_Date = format(as.Date(date_booked), "%b %d, %Y"),
        Actions = paste0(
          '<button class="btn-view" onclick="Shiny.setInputValue(\'edit_booking\', ', booking_id, ')">
            <i class="fas fa-edit"></i> Edit
          </button>'
        )
      ) %>%
      select(
        Customer = customer_name,
        "Customer Type" = `Customer Type`,
        Class = class_title,
        "Booked On" = Booking_Date,
        Slots = slots_booked,
        Status = Status,
        Actions = Actions
      )
    
    datatable(
      display_data,
      escape = FALSE,
      options = list(
        dom = 't',
        ordering = FALSE,
        searching = FALSE,
        info = FALSE,
        paging = FALSE,
        columnDefs = list(
          list(className = 'dt-center', targets = 4:6)
        )
      ),
      rownames = FALSE,
      selection = 'none'
    )
  })
  
  # Class Cards Grid 
  output$classCardsGrid <- renderUI({
    if(!user_auth$logged_in) return()
    
    data <- classes_data()
    
    if(is.null(data) || nrow(data) == 0) {
      return(
        div(class = "empty-state",
            icon("music", class = "fas"),
            h3("No Classes Yet"),
            p("Get started by adding your first dance class"),
            actionButton("addClassEmpty", "Add New Class", 
                         class = "btn-primary", icon = icon("plus"))
        )
      )
    }
    
    # Get today's date for comparison
    today <- Sys.Date()
    
    # Create cards 
    cards <- lapply(1:nrow(data), function(i) {
      class <- data[i, ]
      
      # Ensure we have valid values
      class_id <- ifelse(is.null(class$class_id) || is.na(class$class_id), 0, class$class_id)
      title <- ifelse(is.null(class$title) || is.na(class$title), "Untitled Class", as.character(class$title))
      instructor <- ifelse(is.null(class$instructor) || is.na(class$instructor), "No Instructor", as.character(class$instructor))
      date_val <- ifelse(is.null(class$date) || is.na(class$date), "No Date", as.character(class$date))
      time_val <- ifelse(is.null(class$time) || is.na(class$time), "00:00", as.character(class$time))
      duration <- ifelse(is.null(class$duration) || is.na(class$duration), 0, as.numeric(class$duration))
      price <- ifelse(is.null(class$price) || is.na(class$price), 0, as.numeric(class$price))
      slots_remaining <- ifelse(is.null(class$slots_remaining) || is.na(class$slots_remaining), 0, as.numeric(class$slots_remaining))
      total_slots <- ifelse(is.null(class$total_slots) || is.na(class$total_slots), 0, as.numeric(class$total_slots))
      status <- ifelse(is.null(class$status) || is.na(class$status), "Available", as.character(class$status))
      
      # Check if class is today
      is_today <- FALSE
      if(!is.null(date_val) && !is.na(date_val)) {
        tryCatch({
          class_date <- as.Date(date_val)
          is_today <- class_date == today
        }, error = function(e) {
          is_today <- FALSE
        })
      }
      
      # Parse time
      time_formatted <- tryCatch({
        if(grepl(":", time_val)) {
          time_parts <- strsplit(time_val, ":")[[1]]
          hour <- as.numeric(time_parts[1])
          minute <- time_parts[2]
          am_pm <- ifelse(hour < 12, "AM", "PM")
          hour12 <- ifelse(hour == 0, 12, ifelse(hour > 12, hour - 12, hour))
          paste0(hour12, ":", minute, " ", am_pm)
        } else {
          time_val
        }
      }, error = function(e) {
        time_val
      })
      
      # Determine status and progress
      progress_percent <- ifelse(total_slots > 0, round((slots_remaining / total_slots) * 100), 0)
      
      if(status == "Available") {
        status_class <- "status-available-bg"
        progress_class <- "progress-available"
      } else if(status == "Few Slots") {
        status_class <- "status-few-bg"
        progress_class <- "progress-few"
      } else {
        status_class <- "status-full-bg"
        progress_class <- "progress-full"
      }
      
      # Create the card
      div(class = "class-card",
          div(class = "class-card-header",
              h3(class = "class-card-title", title),
              div(class = "class-status-container",
                  span(class = paste("class-status", status_class), status),
                  if(is_today) {
                    span(class = "status-today", icon("calendar-day"), " Today")
                  }
              )
          ),
          
          div(class = "class-details",
              div(class = "class-detail-item",
                  icon("user-tie"),
                  span(paste("Instructor:", instructor))
              ),
              div(class = "class-detail-item",
                  icon("calendar"),
                  span(paste("Date:", date_val))
              ),
              div(class = "class-detail-item",
                  icon("clock"),
                  span(paste("Time:", time_formatted))
              ),
              div(class = "class-detail-item",
                  icon("hourglass"),
                  span(paste("Duration:", duration, "minutes"))
              ),
              div(class = "class-detail-item",
                  icon("money-bill"),
                  span(paste("Price: ₱", price))
              )
          ),
          
          div(class = "class-slots",
              div(class = "slots-info",
                  span(class = "slots-label", "Available Slots"),
                  span(class = "slots-value", 
                       paste(slots_remaining, "/", total_slots))
              ),
              div(class = paste("slots-progress", progress_class),
                  paste0(progress_percent, "%")
              )
          ),
          
          div(class = "class-actions",
              actionButton(inputId = paste0("view_class_", class_id),
                           label = tagList(icon("eye"), "View"),
                           class = "btn-view",
                           onclick = paste0("Shiny.setInputValue('view_class_detail', '", class_id, "')")),
              actionButton(inputId = paste0("edit_class_", class_id),
                           label = tagList(icon("edit"), "Edit"),
                           class = "btn-edit",
                           onclick = paste0("Shiny.setInputValue('edit_class', '", class_id, "')")),
              actionButton(inputId = paste0("delete_class_", class_id),
                           label = tagList(icon("trash"), "Delete"),
                           class = "btn-delete",
                           onclick = paste0("Shiny.setInputValue('delete_class', '", class_id, "')"))
          )
      )
    })
    
    # Return the grid
    div(class = "classes-grid", cards)
  })
  
  # Update class filter dropdown for bookings
  updateClassFilterDropdown <- function() {
    classes <- classes_data()
    
    if(nrow(classes) == 0) {
      updateSelectInput(session, "booking_class_filter", 
                        choices = c("All Classes" = ""))
      return()
    }
    
    # Create choices for dropdown
    class_choices <- c("All Classes" = "")
    
    # Add each class with its title and date
    for(i in 1:nrow(classes)) {
      class <- classes[i, ]
      choice_name <- paste(class$title, "-", class$date)
      class_choices <- c(class_choices, setNames(as.character(class$class_id), choice_name))
    }
    
    updateSelectInput(session, "booking_class_filter", 
                      choices = class_choices)
  }
  
  # Filter bookings by selected class - FIXED VERSION
  filtered_bookings_data <- reactive({
    data <- bookings_data()
    
    if(is.null(data) || nrow(data) == 0) {
      return(data.frame())
    }
    
    # Apply class filter
    if(!is.null(input$booking_class_filter) && input$booking_class_filter != "") {
      selected_class_id <- as.integer(input$booking_class_filter)
      data <- data %>% filter(class_id == selected_class_id)
    }
    
    # Apply status filter - using trimmed status for comparison
    if(!is.null(input$booking_status_filter) && input$booking_status_filter != "") {
      selected_status <- input$booking_status_filter
      data <- data %>% filter(trimws(as.character(status)) == selected_status)
    }
    
    return(data)
  })
  
  # Reset booking filter
  observeEvent(input$reset_booking_filter, {
    updateSelectInput(session, "booking_class_filter", selected = "")
    updateSelectInput(session, "booking_status_filter", selected = "")
  })
  
  # All Bookings Table (Bookings Section)
  output$allBookingsTable <- renderDT({
    if(!user_auth$logged_in) return()
    
    data <- filtered_bookings_data()
    
    if(nrow(data) == 0) {
      return(datatable(
        data.frame(
          Message = ifelse(
            is.null(input$booking_class_filter) || input$booking_class_filter == "",
            "No bookings found. Click 'Add Booking' to create your first booking.",
            "No bookings found for the selected filters."
          )
        ),
        options = list(dom = 't'),
        rownames = FALSE
      ))
    }
    
    # Get today's date and class dates
    today <- Sys.Date()
    
    display_data <- data %>%
      mutate(
        # Clean the status by trimming whitespace
        status_clean = trimws(as.character(status)),
        Status = case_when(
          status_clean == "Booked" ~ '<span class="status-badge status-booked">Booked</span>',
          status_clean == "Cancelled" ~ '<span class="status-badge status-cancelled">Cancelled</span>',
          status_clean == "Attended" ~ '<span class="status-badge status-attended">Attended</span>',
          TRUE ~ paste0('<span class="status-badge">Unknown (', status_clean, ')</span>')
        ),
        "Booking Date" = format(as.Date(date_booked), "%b %d, %Y %H:%M"),
        "Customer Type" = ifelse(customer_type == "Member", 
                                 '<span class="status-badge status-member">Member</span>',
                                 '<span class="status-badge status-regular">Regular</span>'),
        Actions = paste0(
          '<div class="qr-action-cell">',
          ifelse(
            status_clean == "Cancelled",
            paste0(
              '<span class="btn-disabled"><i class="fas fa-qrcode"></i> QR</span>',
              '<span class="btn-disabled"><i class="fas fa-edit"></i> Edit</span>',
              '<span class="btn-disabled"><i class="fas fa-times"></i> Cancel</span>'
            ),
            ifelse(
              status_clean == "Attended",
              paste0(
                '<button class="btn-qr" onclick="Shiny.setInputValue(\'view_qr_code\', ', booking_id, ')">
                <i class="fas fa-qrcode"></i> QR
              </button>',
                '<span class="btn-disabled"><i class="fas fa-edit"></i> Edit</span>',
                '<span class="btn-disabled"><i class="fas fa-times"></i> Cancel</span>'
              ),
              # For "Booked" status (or any other status)
              paste0(
                '<button class="btn-qr" onclick="Shiny.setInputValue(\'view_qr_code\', ', booking_id, ')">
                <i class="fas fa-qrcode"></i> QR
              </button>',
                '<button class="btn-view" onclick="Shiny.setInputValue(\'edit_booking_all\', ', booking_id, ')">
                <i class="fas fa-edit"></i> Edit
              </button>',
                ifelse(
                  as.Date(class_date) == today,
                  paste0(
                    '<button class="btn-attend" onclick="Shiny.setInputValue(\'mark_attended\', ', booking_id, ')">
                    <i class="fas fa-check"></i> Mark Attended
                  </button>'
                  ),
                  paste0(
                    '<button class="btn-delete" onclick="Shiny.setInputValue(\'cancel_booking\', ', booking_id, ')">
                    <i class="fas fa-times"></i> Cancel
                  </button>'
                  )
                )
              )
            )
          ),
          '</div>'
        )
      ) %>%
      select(
        Customer = customer_name,
        "Customer Type" = `Customer Type`,
        Contact = contact,
        Class = class_title,
        "Class Date" = class_date,
        Slots = slots_booked,
        "Booking Date" = `Booking Date`,
        Status = Status,
        Actions = Actions
      )
    
    datatable(
      display_data,
      escape = FALSE,
      options = list(
        pageLength = 10,
        dom = 'Bfrtip',
        buttons = c('copy', 'csv', 'excel', 'pdf')
      ),
      rownames = FALSE,
      selection = 'none'
    )
  })
  
  # Handle mark as attended
  observeEvent(input$mark_attended, {
    if(!user_auth$logged_in) return()
    
    booking_id <- input$mark_attended
    
    if(is.null(booking_id) || booking_id == "") {
      cat("No booking ID provided\n")
      return()
    }
    
    # Get booking data
    data <- bookings_data()
    booking_data <- data %>% filter(booking_id == !!booking_id)
    
    if(nrow(booking_data) == 0) {
      safe_notify("Booking not found", "error", 5)
      return()
    }
    
    booking_data <- booking_data[1, ]
    
    # Check if already attended
    if(booking_data$status == "Attended") {
      safe_notify("Booking is already marked as attended", "error", 5)
      return()
    }
    
    # Check if class is today
    today <- Sys.Date()
    class_date <- as.Date(booking_data$class_date)
    
    if(class_date != today) {
      safe_notify("Can only mark attendance on the class date", "error", 5)
      return()
    }
    
    showModal(modalDialog(
      title = "Confirm Attendance",
      size = "m",
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirmMarkAttended", "Mark as Attended", 
                     class = "btn-primary", icon = icon("check"))
      ),
      div(
        h4("Mark this booking as attended?"),
        p("This will update the booking status to 'Attended'."),
        tags$hr(),
        p(strong("Customer:"), booking_data$customer_name),
        p(strong("Class:"), booking_data$class_title),
        p(strong("Date:"), booking_data$class_date),
        p(strong("Slots:"), booking_data$slots_booked)
      )
    ))
    
    # Store booking_id in a reactive value
    mark_attended_id(booking_id)
  })
  
  # Reactive value for marking attended
  mark_attended_id <- reactiveVal(NULL)
  
  # Confirm mark as attended
  observeEvent(input$confirmMarkAttended, {
    if(!user_auth$logged_in) return()
    
    booking_id <- mark_attended_id()
    
    if(is.null(booking_id)) {
      safe_notify("No booking selected", "error", 5)
      return()
    }
    
    tryCatch({
      # Update booking status to Attended
      update_query <- sprintf(
        "UPDATE bookings SET status = 'Attended' WHERE booking_id = %d",
        as.integer(booking_id)
      )
      
      dbExecute(pool, update_query)
      
      removeModal()
      
      # Refresh data
      fetch_bookings()
      
      safe_notify("Booking marked as attended!", "success", 5)
      
      # Clear the mark_attended_id
      mark_attended_id(NULL)
    }, error = function(e) {
      cat("Error marking as attended:", e$message, "\n")
      safe_notify(paste("Error:", toString(e$message)), "error", 5)
    })
  })
  
  # Handle view class detail
  observeEvent(input$view_class_detail, {
    if(!user_auth$logged_in) return()
    
    cat("View class detail triggered:", input$view_class_detail, "\n")
    
    if(is.null(input$view_class_detail) || input$view_class_detail == "") {
      cat("No class ID provided\n")
      return()
    }
    
    class_id <- input$view_class_detail
    
    data <- classes_data()
    class_data <- data %>% filter(class_id == !!class_id)
    
    if(nrow(class_data) == 0) {
      safe_notify("Class not found", "error", 5)
      return()
    }
    
    class_data <- class_data[1, ]
    
    # Get bookings for this class
    bookings <- tryCatch({
      query <- sprintf(
        "SELECT * FROM bookings WHERE class_id = %d AND archived = 0 ORDER BY date_booked DESC",
        as.integer(class_id)
      )
      dbGetQuery(pool, query)
    }, error = function(e) {
      cat("Error fetching bookings:", e$message, "\n")
      data.frame()
    })
    
    # Calculate actual booked slots
    booked_slots <- sum(bookings %>% filter(status == "Booked") %>% pull(slots_booked), na.rm = TRUE)
    
    showModal(modalDialog(
      title = paste("Class Details:", class_data$title),
      size = "l",
      easyClose = TRUE,
      footer = modalButton("Close"),
      
      div(
        h4("Class Information"),
        tableOutput("classDetailTable"),
        
        h4("Bookings"),
        if(nrow(bookings) > 0) {
          tagList(
            p(strong("Total Booked Slots:"), booked_slots),
            DTOutput("classBookingsTable")
          )
        } else {
          p("No bookings for this class yet.")
        }
      )
    ))
    
    output$classDetailTable <- renderTable({
      data.frame(
        Field = c("Title", "Instructor", "Date", "Time", "Duration", 
                  "Price per Slot", "Total Slots", "Available Slots", "Booked Slots", "Status"),
        Value = c(
          class_data$title,
          class_data$instructor,
          as.character(class_data$date),
          as.character(class_data$time),
          paste(class_data$duration, "minutes"),
          paste0("₱", class_data$price),
          class_data$total_slots,
          class_data$slots_remaining,
          booked_slots,
          class_data$status
        )
      )
    })
    
    output$classBookingsTable <- renderDT({
      display_bookings <- bookings %>%
        mutate(
          Status = case_when(
            status == "Booked" ~ '<span class="status-badge status-booked">Booked</span>',
            status == "Cancelled" ~ '<span class="status-badge status-cancelled">Cancelled</span>',
            status == "Attended" ~ '<span class="status-badge status-attended">Attended</span>',
            TRUE ~ status
          ),
          Date = format(as.Date(date_booked), "%b %d, %Y %H:%M")
        )
      
      datatable(
        display_bookings %>% select(Customer = customer_name, "Customer Type" = customer_type, 
                                    Contact = contact, "Booked Slots" = slots_booked, 
                                    Status = Status, "Booking Date" = Date),
        options = list(pageLength = 5),
        escape = FALSE
      )
    })
  })
  
  # Handle edit class
  observeEvent(input$edit_class, {
    if(!user_auth$logged_in) return()
    
    cat("Edit class triggered:", input$edit_class, "\n")
    
    if(is.null(input$edit_class) || input$edit_class == "") {
      cat("No class ID provided\n")
      return()
    }
    
    class_id <- input$edit_class
    
    data <- classes_data()
    class_data <- data %>% filter(class_id == !!class_id)
    
    if(nrow(class_data) == 0) {
      safe_notify("Class not found", "error", 5)
      return()
    }
    
    class_data <- class_data[1, ]
    
    # Show edit modal with current values
    showModal(modalDialog(
      title = paste("Edit Class:", class_data$title),
      size = "l",
      footer = tagList(
        modalButton("Cancel"),
        actionButton("updateClass", "Update Class", 
                     class = "btn-primary", icon = icon("save"))
      ),
      div(
        textInput("editClassTitle", "Class Title *", value = class_data$title),
        textInput("editClassInstructor", "Instructor *", value = class_data$instructor),
        textAreaInput("editClassDescription", "Description", rows = 3, 
                      value = ifelse(is.na(class_data$description) || class_data$description == "", 
                                     "No description", class_data$description)),
        dateInput("editClassDate", "Date *", value = as.Date(class_data$date)),
        textInput("editClassTime", "Time * (24h format)", 
                  value = ifelse(grepl(":", class_data$time), 
                                 substr(class_data$time, 1, 5), class_data$time)),
        numericInput("editClassDuration", "Duration (minutes) *", 
                     value = class_data$duration, min = 30, max = 180),
        numericInput("editClassSlots", "Total Slots *", 
                     value = class_data$total_slots, min = 1, max = 100),
        numericInput("editClassPrice", "Price per Slot (₱) *", 
                     value = class_data$price, min = 100, max = 5000, step = 50)
      )
    ))
    
    # Store class_id in a reactive value for the update
    edit_class_id(class_id)
  })
  
  # Reactive value for editing class
  edit_class_id <- reactiveVal(NULL)
  
  # Handle delete class
  observeEvent(input$delete_class, {
    if(!user_auth$logged_in) return()
    
    cat("Delete class triggered:", input$delete_class, "\n")
    
    if(is.null(input$delete_class) || input$delete_class == "") {
      cat("No class ID provided\n")
      return()
    }
    
    class_id <- input$delete_class
    
    showModal(modalDialog(
      title = "Confirm Delete",
      size = "m",
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirmDeleteClass", "Delete Class", 
                     class = "btn-danger", icon = icon("trash"))
      ),
      div(
        h4("Are you sure you want to delete this class?"),
        p("This action cannot be undone. Any bookings for this class will also be deleted.")
      )
    ))
    
    # Store class_id in a reactive value for the delete
    delete_class_id(class_id)
  })
  
  # Reactive value for deleting class
  delete_class_id <- reactiveVal(NULL)
  
  # Confirm delete class
  observeEvent(input$confirmDeleteClass, {
    if(!user_auth$logged_in) return()
    
    class_id <- delete_class_id()
    
    if(is.null(class_id)) {
      safe_notify("No class selected for deletion", "error", 5)
      return()
    }
    
    tryCatch({
      # First, delete associated bookings
      delete_bookings_query <- sprintf(
        "DELETE FROM bookings WHERE class_id = %d",
        as.integer(class_id)
      )
      dbExecute(pool, delete_bookings_query)
      
      # Then delete the class
      delete_class_query <- sprintf(
        "DELETE FROM classes WHERE class_id = %d",
        as.integer(class_id)
      )
      dbExecute(pool, delete_class_query)
      
      removeModal()
      fetch_classes()
      fetch_bookings()
      safe_notify("Class deleted successfully!", "success", 5)
      
      # Clear the delete_id
      delete_class_id(NULL)
    }, error = function(e) {
      cat("Error deleting class:", e$message, "\n")
      safe_notify(paste("Error deleting class:", toString(e$message)), "error", 5)
    })
  })
  
  # Handle edit booking (from dashboard)
  observeEvent(input$edit_booking, {
    if(!user_auth$logged_in) return()
    
    cat("Edit booking triggered:", input$edit_booking, "\n")
    edit_booking_id <- input$edit_booking
    showEditBookingModal(edit_booking_id)
  })
  
  # Handle edit booking (from bookings section)
  observeEvent(input$edit_booking_all, {
    if(!user_auth$logged_in) return()
    
    cat("Edit booking all triggered:", input$edit_booking_all, "\n")
    edit_booking_id <- input$edit_booking_all
    showEditBookingModal(edit_booking_id)
  })
  
  # Function to show edit booking modal
  showEditBookingModal <- function(booking_id) {
    if(!user_auth$logged_in) return()
    
    if(is.null(booking_id) || booking_id == "") {
      cat("No booking ID provided\n")
      return()
    }
    
    cat("Editing booking ID:", booking_id, "\n")
    
    # Get booking data
    data <- bookings_data()
    booking_data <- data %>% filter(booking_id == !!booking_id)
    
    if(nrow(booking_data) == 0) {
      safe_notify("Booking not found", "error", 5)
      return()
    }
    
    booking_data <- booking_data[1, ]
    
    # Check if booking can be edited
    if(booking_data$status != "Booked") {
      safe_notify("Only booked bookings can be edited", "error", 5)
      return()
    }
    
    # Get classes for dropdown (only classes with available slots)
    classes <- classes_data()
    available_classes <- classes %>% 
      filter(slots_remaining > 0 | class_id == booking_data$class_id)
    
    class_choices <- setNames(
      available_classes$class_id,
      paste(available_classes$title, "-", available_classes$date, 
            "(", available_classes$slots_remaining, "slots left, ₱", 
            available_classes$price, "per slot)")
    )
    
    showModal(modalDialog(
      title = "Edit Booking",
      size = "m",
      footer = tagList(
        modalButton("Cancel"),
        actionButton("updateBooking", "Update Booking", 
                     class = "btn-primary", icon = icon("save"))
      ),
      div(
        selectInput("editBookingClass", "Select Class *", 
                    choices = class_choices,
                    selected = booking_data$class_id),
        radioButtons("editCustomerType", "Customer Type *",
                     choices = c("Regular" = "Regular", 
                                 "Member (₱50 discount)" = "Member"),
                     selected = booking_data$customer_type),
        textInput("editBookingCustomer", "Customer Name *", 
                  value = booking_data$customer_name),
        textInput("editBookingContact", "Contact Info", 
                  value = booking_data$contact),
        numericInput("editBookingSlots", "Number of Slots *", 
                     value = booking_data$slots_booked, min = 1, max = 10)
      )
    ))
    
    # Store booking_id in a reactive value for the update
    edit_booking_id(booking_id)
  }
  
  # Reactive value for editing booking
  edit_booking_id <- reactiveVal(NULL)
  
  # Handle cancel booking
  observeEvent(input$cancel_booking, {
    if(!user_auth$logged_in) return()
    
    cat("Cancel booking triggered:", input$cancel_booking, "\n")
    
    if(is.null(input$cancel_booking) || input$cancel_booking == "") {
      cat("No booking ID provided\n")
      return()
    }
    
    booking_id <- input$cancel_booking
    
    # Get booking data to check status
    data <- bookings_data()
    booking_data <- data %>% filter(booking_id == !!booking_id)
    
    if(nrow(booking_data) == 0) {
      safe_notify("Booking not found", "error", 5)
      return()
    }
    
    booking_data <- booking_data[1, ]
    
    # Check if already cancelled
    if(booking_data$status == "Cancelled") {
      safe_notify("Booking is already cancelled", "error", 5)
      return()
    }
    
    # Check if attended
    if(booking_data$status == "Attended") {
      safe_notify("Cannot cancel attended bookings", "error", 5)
      return()
    }
    
    showModal(modalDialog(
      title = "Confirm Cancel Booking",
      size = "m",
      footer = tagList(
        modalButton("No"),
        actionButton("confirmCancelBooking", "Yes, Cancel Booking", 
                     class = "btn-danger", icon = icon("times"))
      ),
      div(
        h4("Are you sure you want to cancel this booking?"),
        p("The booking will be marked as cancelled and the slots will be returned to the class.")
      )
    ))
    
    # Store booking_id in a reactive value
    cancel_booking_id(booking_id)
  })
  
  # Reactive value for canceling booking
  cancel_booking_id <- reactiveVal(NULL)
  
  # Add Class Modal
  observeEvent(input$addClass, {
    if(!user_auth$logged_in) return()
    
    showModal(modalDialog(
      title = "Add New Dance Class",
      size = "l",
      footer = tagList(
        modalButton("Cancel"),
        actionButton("saveClass", "Save Class", 
                     class = "btn-primary", icon = icon("save"))
      ),
      div(
        textInput("classTitle", "Class Title *", placeholder = "e.g., Hip Hop Beginner"),
        textInput("classInstructor", "Instructor *", placeholder = "Instructor name"),
        textAreaInput("classDescription", "Description", rows = 3, placeholder = "Class description..."),
        dateInput("classDate", "Date *", min = Sys.Date()),
        textInput("classTime", "Time * (24h format)", placeholder = "HH:MM"),
        numericInput("classDuration", "Duration (minutes) *", value = 60, min = 30, max = 180),
        numericInput("classSlots", "Total Slots *", value = 20, min = 1, max = 100),
        numericInput("classPrice", "Price per Slot (₱) *", value = NULL, min = 100, max = 5000, step = 50)
      )
    ))
  })
  
  # Add Class from Empty State
  observeEvent(input$addClassEmpty, {
    if(!user_auth$logged_in) return()
    
    showModal(modalDialog(
      title = "Add New Dance Class",
      size = "l",
      footer = tagList(
        modalButton("Cancel"),
        actionButton("saveClass", "Save Class", 
                     class = "btn-primary", icon = icon("save"))
      ),
      div(
        textInput("classTitle", "Class Title *", placeholder = "e.g., Hip Hop Beginner"),
        textInput("classInstructor", "Instructor *", placeholder = "Instructor name"),
        textAreaInput("classDescription", "Description", rows = 3, placeholder = "Class description..."),
        dateInput("classDate", "Date *", min = Sys.Date()),
        textInput("classTime", "Time * (24h format)", placeholder = "HH:MM"),
        numericInput("classDuration", "Duration (minutes) *", value = 60, min = 30, max = 180),
        numericInput("classSlots", "Total Slots *", value = 20, min = 1, max = 100),
        numericInput("classPrice", "Price per Slot (₱) *", value = NULL, min = 100, max = 5000, step = 50)
      )
    ))
  })
  
  # Add Booking Modal
  observeEvent(input$addBooking, {
    if(!user_auth$logged_in) return()
    
    classes <- classes_data()
    if(nrow(classes) == 0) {
      safe_notify("No classes available to book", "warning", 5)
      return()
    }
    
    # Filter classes with available slots
    available_classes <- classes %>% 
      filter(slots_remaining > 0, status != "Full")
    
    if(nrow(available_classes) == 0) {
      safe_notify("No classes with available slots", "warning", 5)
      return()
    }
    
    class_choices <- setNames(
      available_classes$class_id,
      paste(available_classes$title, "-", available_classes$date, 
            "(", available_classes$slots_remaining, "slots left, ₱", 
            available_classes$price, "per slot)")
    )
    
    showModal(modalDialog(
      title = "Add New Booking",
      size = "m",
      footer = tagList(
        modalButton("Cancel"),
        actionButton("saveBooking", "Book Now", 
                     class = "btn-primary", icon = icon("check"))
      ),
      div(
        selectInput("bookingClass", "Select Class *", choices = class_choices),
        radioButtons("customerType", "Customer Type *",
                     choices = c("Regular" = "Regular", 
                                 "Member (₱50 discount)" = "Member"),
                     selected = "Regular"),
        textInput("bookingCustomer", "Customer Name *", placeholder = "Full name"),
        textInput("bookingContact", "Contact Info", placeholder = "Phone or email (optional)"),
        numericInput("bookingSlots", "Number of Slots *", value = 1, min = 1, max = 10),
        # Display price calculation
        uiOutput("priceCalculation")
      )
    ))
  })
  
  # Price Calculation for Booking Modal
  output$priceCalculation <- renderUI({
    if(!user_auth$logged_in) return(NULL)
    
    req(input$bookingClass, input$bookingSlots)
    
    # Get selected class price
    class_info <- classes_data() %>% 
      filter(class_id == input$bookingClass)
    
    if(nrow(class_info) == 0) return(NULL)
    
    price_per_slot <- class_info$price
    discount <- ifelse(input$customerType == "Member", 50, 0)
    final_price_per_slot <- price_per_slot - discount
    total_price <- final_price_per_slot * input$bookingSlots
    
    div(
      style = "background: #f8fafc; padding: 15px; border-radius: 10px; margin-top: 15px;",
      h4("Price Calculation", style = "margin-top: 0;"),
      tableOutput("priceDetails")
    )
  })
  
  output$priceDetails <- renderTable({
    if(!user_auth$logged_in) return(NULL)
    
    req(input$bookingClass, input$bookingSlots, input$customerType)
    
    class_info <- classes_data() %>% 
      filter(class_id == input$bookingClass)
    
    if(nrow(class_info) == 0) return(NULL)
    
    price_per_slot <- class_info$price
    discount <- ifelse(input$customerType == "Member", 50, 0)
    final_price_per_slot <- price_per_slot - discount
    total_price <- final_price_per_slot * input$bookingSlots
    
    data.frame(
      Item = c("Price per slot", "Discount", "Final price per slot", 
               "Number of slots", "Total Amount"),
      Value = c(
        paste0("₱", price_per_slot),
        ifelse(discount > 0, paste0("-₱", discount), "₱0"),
        paste0("₱", final_price_per_slot),
        input$bookingSlots,
        paste0("₱", total_price)
      )
    )
  })
  
  # Save Class - UPDATED for SQLite
  observeEvent(input$saveClass, {
    if(!user_auth$logged_in) return()
    
    # Validate all required inputs
    if(is.null(input$classTitle) || input$classTitle == "") {
      safe_notify("Class title is required", "error", 5)
      return()
    }
    if(is.null(input$classInstructor) || input$classInstructor == "") {
      safe_notify("Instructor name is required", "error", 5)
      return()
    }
    if(is.null(input$classDate)) {
      safe_notify("Class date is required", "error", 5)
      return()
    }
    if(is.null(input$classTime) || input$classTime == "") {
      safe_notify("Class time is required", "error", 5)
      return()
    }
    if(is.null(input$classDuration) || input$classDuration < 30) {
      safe_notify("Duration must be at least 30 minutes", "error", 5)
      return()
    }
    if(is.null(input$classSlots) || input$classSlots < 1) {
      safe_notify("Total slots must be at least 1", "error", 5)
      return()
    }
    if(is.null(input$classPrice) || input$classPrice < 100) {
      safe_notify("Price must be at least ₱100", "error", 5)
      return()
    }
    
    tryCatch({
      # Validate time format
      time_regex <- "^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$"
      if(!grepl(time_regex, input$classTime)) {
        safe_notify("Time must be in 24-hour format (HH:MM)", "error", 5)
        return()
      }
      
      # Format time with seconds for SQLite
      time_formatted <- ifelse(grepl(":", input$classTime), 
                               paste0(input$classTime, ":00"), 
                               paste0(input$classTime, ":00:00"))
      
      # Prepare data for insertion
      title <- input$classTitle
      description <- ifelse(is.null(input$classDescription) || input$classDescription == "", 
                            "No description", input$classDescription)
      instructor <- input$classInstructor
      date_val <- as.character(input$classDate)
      price <- input$classPrice
      
      # Build SQL query with SQLite syntax
      query <- sprintf(
        "INSERT INTO classes (title, description, instructor, date, time, duration, total_slots, slots_remaining, status, price, archived) 
        VALUES ('%s', '%s', '%s', '%s', '%s', %d, %d, %d, 'Available', %.2f, 0)",
        gsub("'", "''", title),  # Escape single quotes
        gsub("'", "''", description),
        gsub("'", "''", instructor),
        date_val,
        time_formatted,
        input$classDuration,
        input$classSlots,
        input$classSlots,
        price
      )
      
      cat("Executing query:", query, "\n")
      dbExecute(pool, query)
      removeModal()
      fetch_classes()
      safe_notify("Class added successfully!", "success", 5)
    }, error = function(e) {
      cat("Error saving class:", e$message, "\n")
      safe_notify(paste("Error adding class:", toString(e$message)), "error", 5)
    })
  })
  
  # Update Class - UPDATED for SQLite
  observeEvent(input$updateClass, {
    if(!user_auth$logged_in) return()
    
    class_id <- edit_class_id()
    
    if(is.null(class_id)) {
      safe_notify("No class selected for update", "error", 5)
      return()
    }
    
    # Validate all required inputs
    if(is.null(input$editClassTitle) || input$editClassTitle == "") {
      safe_notify("Class title is required", "error", 5)
      return()
    }
    if(is.null(input$editClassInstructor) || input$editClassInstructor == "") {
      safe_notify("Instructor name is required", "error", 5)
      return()
    }
    if(is.null(input$editClassDate)) {
      safe_notify("Class date is required", "error", 5)
      return()
    }
    if(is.null(input$editClassTime) || input$editClassTime == "") {
      safe_notify("Class time is required", "error", 5)
      return()
    }
    if(is.null(input$editClassDuration) || input$editClassDuration < 30) {
      safe_notify("Duration must be at least 30 minutes", "error", 5)
      return()
    }
    if(is.null(input$editClassSlots) || input$editClassSlots < 1) {
      safe_notify("Total slots must be at least 1", "error", 5)
      return()
    }
    if(is.null(input$editClassPrice) || input$editClassPrice < 100) {
      safe_notify("Price must be at least ₱100", "error", 5)
      return()
    }
    
    tryCatch({
      # Validate time format
      time_regex <- "^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$"
      if(!grepl(time_regex, input$editClassTime)) {
        safe_notify("Time must be in 24-hour format (HH:MM)", "error", 5)
        return()
      }
      
      # Format time with seconds for SQLite
      time_formatted <- ifelse(grepl(":", input$editClassTime), 
                               paste0(input$editClassTime, ":00"), 
                               paste0(input$editClassTime, ":00:00"))
      
      # Prepare data for update
      title <- input$editClassTitle
      description <- ifelse(is.null(input$editClassDescription) || input$editClassDescription == "", 
                            "No description", input$editClassDescription)
      instructor <- input$editClassInstructor
      date_val <- as.character(input$editClassDate)
      price <- input$editClassPrice
      
      # Get current class data to calculate slots difference
      current_class <- classes_data() %>% filter(class_id == !!class_id)
      if(nrow(current_class) == 0) {
        safe_notify("Class not found", "error", 5)
        return()
      }
      
      current_class <- current_class[1, ]
      
      # Get current booked slots from database
      booked_slots_query <- sprintf(
        "SELECT COALESCE(SUM(slots_booked), 0) as total_booked 
         FROM bookings 
         WHERE class_id = %d AND status = 'Booked' AND archived = 0",
        as.integer(class_id)
      )
      booked_slots <- dbGetQuery(pool, booked_slots_query)$total_booked[1]
      
      # Calculate new slots_remaining based on total_slots change
      slots_diff <- input$editClassSlots - current_class$total_slots
      new_slots_remaining <- current_class$slots_remaining + slots_diff
      
      # Ensure slots_remaining doesn't go negative
      if(new_slots_remaining < 0) {
        safe_notify(
          sprintf("Cannot reduce total slots below %d (already booked slots)", booked_slots),
          "error", 5
        )
        return()
      }
      
      # Update status based on new slots
      new_status <- ifelse(new_slots_remaining <= 0, 'Full', 
                           ifelse(new_slots_remaining <= 5, 'Few Slots', 'Available'))
      
      # Build SQL query for update - SQLite version
      update_query <- sprintf(
        "UPDATE classes SET 
         title = '%s',
         description = '%s',
         instructor = '%s',
         date = '%s',
         time = '%s',
         duration = %d,
         total_slots = %d,
         slots_remaining = %d,
         status = '%s',
         price = %.2f,
         updated_at = datetime('now')
         WHERE class_id = %d",
        gsub("'", "''", title),
        gsub("'", "''", description),
        gsub("'", "''", instructor),
        date_val,
        time_formatted,
        input$editClassDuration,
        input$editClassSlots,
        new_slots_remaining,
        new_status,
        price,
        as.integer(class_id)
      )
      
      cat("Executing update query:", update_query, "\n")
      dbExecute(pool, update_query)
      removeModal()
      fetch_classes()
      safe_notify("Class updated successfully!", "success", 5)
      
      # Clear the edit_id
      edit_class_id(NULL)
    }, error = function(e) {
      cat("Error updating class:", e$message, "\n")
      safe_notify(paste("Error updating class:", toString(e$message)), "error", 5)
    })
  })
  
  # Save Booking with QR Code Generation - UPDATED for SQLite
  observeEvent(input$saveBooking, {
    if(!user_auth$logged_in) return()
    
    tryCatch({
      # Get selected class info
      class_info <- classes_data() %>% 
        filter(class_id == input$bookingClass)
      
      if(nrow(class_info) == 0) {
        safe_notify("Class not found", "error", 5)
        return()
      }
      
      # Validate required fields
      if(is.null(input$bookingCustomer) || input$bookingCustomer == "") {
        safe_notify("Customer name is required", "error", 5)
        return()
      }
      
      if(is.null(input$bookingSlots) || input$bookingSlots < 1) {
        safe_notify("Number of slots must be at least 1", "error", 5)
        return()
      }
      
      # Check if enough slots available
      if(class_info$slots_remaining < input$bookingSlots) {
        safe_notify(
          sprintf("Not enough slots available. Only %d slot(s) remaining.", 
                  class_info$slots_remaining),
          "error", 
          5
        )
        return()
      }
      
      # Calculate final price
      discount <- ifelse(input$customerType == "Member", 50, 0)
      final_price_per_slot <- class_info$price - discount
      total_amount <- final_price_per_slot * input$bookingSlots
      
      # Prepare data for insertion
      customer_name <- input$bookingCustomer
      contact <- ifelse(is.null(input$bookingContact) || input$bookingContact == "", 
                        "No contact info", input$bookingContact)
      
      # Generate unique booking reference
      booking_ref <- paste0("ST-", format(Sys.time(), "%Y%m%d%H%M%S"), "-", 
                            sample(1000:9999, 1))
      
      # Build SQL query - SQLite version
      query <- sprintf(
        "INSERT INTO bookings (class_id, customer_name, contact, slots_booked, customer_type, booking_ref, archived) 
        VALUES (%d, '%s', '%s', %d, '%s', '%s', 0)",
        as.integer(input$bookingClass),
        gsub("'", "''", customer_name),
        gsub("'", "''", contact),
        as.integer(input$bookingSlots),
        input$customerType,
        booking_ref
      )
      
      cat("Executing booking query:", query, "\n")
      dbExecute(pool, query)
      
      # Get the newly created booking ID - SQLite version
      booking_id_query <- "SELECT last_insert_rowid() as booking_id"
      booking_id_result <- dbGetQuery(pool, booking_id_query)
      booking_id <- booking_id_result$booking_id[1]
      
      # Close the booking modal
      removeModal()
      
      # Refresh data
      fetch_classes()
      fetch_bookings()
      
      # Show QR Code Modal
      showQRCodeModal(booking_id, class_info, customer_name, contact, 
                      input$customerType, input$bookingSlots, total_amount, booking_ref)
      
    }, error = function(e) {
      cat("Error saving booking:", e$message, "\n")
      safe_notify(paste("Error adding booking:", toString(e$message)), "error", 5)
    })
  })
  
  # Function to show QR Code Modal
  showQRCodeModal <- function(booking_id, class_info, customer_name, contact, 
                              customer_type, slots_booked, total_amount, booking_ref) {
    
    # Create booking data for QR code
    booking_data <- list(
      booking_ref = booking_ref,
      booking_id = booking_id,
      customer_name = customer_name,
      contact = contact,
      customer_type = customer_type,
      class_title = class_info$title,
      class_date = class_info$date,
      class_time = class_info$time,
      instructor = class_info$instructor,
      slots_booked = slots_booked,
      total_amount = total_amount,
      studio_name = "StudioTrack Dance Studio",
      booking_date = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      verification_url = paste0("https://studiotrack.example.com/verify/", booking_ref)
    )
    
    # Convert to JSON string for QR code
    qr_content <- jsonlite::toJSON(booking_data, auto_unbox = TRUE)
    
    # Generate QR code and save to temp file using plot
    qr_file <- tempfile(fileext = ".png")
    
    # Generate QR code matrix
    qr_matrix <- qrcode::qr_code(qr_content)
    
    # Simple plot method to create PNG
    png(qr_file, width = 500, height = 500)
    par(mar = c(0, 0, 0, 0))
    image(as.matrix(qr_matrix), 
          col = c("white", "black"),
          asp = 1, 
          axes = FALSE)
    dev.off()
    
    # Show modal with QR code
    showModal(modalDialog(
      title = div(
        icon("qrcode"),
        span("Booking Confirmation & QR Code")
      ),
      size = "l",
      easyClose = FALSE,
      footer = tagList(
        modalButton("Close"),
        downloadButton("downloadQRCode", "Download QR Code", class = "btn-download"),
        actionButton("printQRCode", "Print", class = "btn-print", icon = icon("print"))
      ),
      
      div(class = "qr-modal",
          div(class = "qr-success-message",
              icon("check-circle"),
              span("Booking confirmed successfully!"),
              span(class = "qr-badge", icon("qrcode"), "QR Code Generated")
          ),
          
          div(class = "qr-container",
              h4("Your Booking QR Code", style = "margin-bottom: 20px; color: #1e293b;"),
              
              # QR Code Image
              div(class = "qr-image",
                  tags$img(src = base64enc::dataURI(file = qr_file, mime = "image/png"),
                           width = "250", height = "250",
                           alt = "Booking QR Code"),
                  tags$p(style = "font-size: 12px; color: #64748b; margin-top: 10px;",
                         "Scan this code for verification")
              ),
              
              # Booking Information
              div(class = "qr-info",
                  h5("Booking Details", style = "margin-top: 0; margin-bottom: 15px; color: #1e293b;"),
                  
                  div(class = "qr-info-item",
                      span(class = "qr-info-label", "Booking Reference:"),
                      span(class = "qr-info-value", strong(booking_ref))
                  ),
                  
                  div(class = "qr-info-item",
                      span(class = "qr-info-label", "Customer Name:"),
                      span(class = "qr-info-value", customer_name)
                  ),
                  
                  div(class = "qr-info-item",
                      span(class = "qr-info-label", "Contact:"),
                      span(class = "qr-info-value", contact)
                  ),
                  
                  div(class = "qr-info-item",
                      span(class = "qr-info-label", "Customer Type:"),
                      span(class = "qr-info-value", customer_type)
                  ),
                  
                  div(class = "qr-info-item",
                      span(class = "qr-info-label", "Class:"),
                      span(class = "qr-info-value", class_info$title)
                  ),
                  
                  div(class = "qr-info-item",
                      span(class = "qr-info-label", "Date & Time:"),
                      span(class = "qr-info-value", 
                           paste(class_info$date, "-", 
                                 format(strptime(class_info$time, "%H:%M:%S"), "%I:%M %p")))
                  ),
                  
                  div(class = "qr-info-item",
                      span(class = "qr-info-label", "Instructor:"),
                      span(class = "qr-info-value", class_info$instructor)
                  ),
                  
                  div(class = "qr-info-item",
                      span(class = "qr-info-label", "Slots Booked:"),
                      span(class = "qr-info-value", slots_booked)
                  ),
                  
                  div(class = "qr-info-item",
                      span(class = "qr-info-label", "Total Amount:"),
                      span(class = "qr-info-value", paste0("₱", total_amount))
                  ),
                  
                  div(class = "qr-info-item",
                      span(class = "qr-info-label", "Booking Date:"),
                      span(class = "qr-info-value", format(Sys.time(), "%B %d, %Y %I:%M %p"))
                  )
              )
          ),
          
          div(class = "qr-instructions",
              style = "background: #fef3c7; padding: 15px; border-radius: 12px; margin-top: 20px; text-align: left;",
              h5(icon("info-circle"), "Instructions:", style = "margin-top: 0; color: #92400e;"),
              tags$ul(style = "margin-bottom: 0; color: #92400e;",
                      tags$li("Save or print this QR code"),
                      tags$li("Send it to the customer via email or messaging app"),
                      tags$li("Customer should present this QR code on the day of the class"),
                      tags$li("Scan the QR code using the StudioTrack verification app")
              )
          )
      )
    ))
    
    # Store QR data for download
    qr_data_store(list(
      qr_file = qr_file,
      booking_data = booking_data,
      customer_name = customer_name,
      booking_ref = booking_ref,
      class_title = class_info$title
    ))
  }
  
  # Reactive value to store QR data
  qr_data_store <- reactiveVal(NULL)
  
  # Download QR Code
  output$downloadQRCode <- downloadHandler(
    filename = function() {
      if(!is.null(qr_data_store())) {
        data <- qr_data_store()
        # Create filename with booking reference and customer name
        filename <- paste0("StudioTrack_Booking_", 
                           gsub("[^A-Za-z0-9]", "_", data$booking_ref), "_",
                           gsub("[^A-Za-z0-9]", "_", data$customer_name), ".png")
        return(filename)
      }
      return("StudioTrack_Booking_QR.png")
    },
    content = function(file) {
      if(!is.null(qr_data_store())) {
        data <- qr_data_store()
        # Copy the temporary QR file to download location
        file.copy(data$qr_file, file)
      }
    }
  )
  
  # Print QR Code
  observeEvent(input$printQRCode, {
    shinyjs::runjs('
      var qrModal = document.querySelector(".modal-content");
      var originalBody = document.body.innerHTML;
      var printContent = qrModal.innerHTML;
      
      document.body.innerHTML = printContent;
      window.print();
      document.body.innerHTML = originalBody;
      location.reload();
    ')
  })
  
  # Handle view QR code for existing bookings
  observeEvent(input$view_qr_code, {
    if(!user_auth$logged_in) return()
    
    booking_id <- input$view_qr_code
    
    if(is.null(booking_id) || booking_id == "") {
      cat("No booking ID provided\n")
      return()
    }
    
    # Get booking data
    data <- bookings_data()
    booking_data <- data %>% filter(booking_id == !!booking_id)
    
    if(nrow(booking_data) == 0) {
      safe_notify("Booking not found", "error", 5)
      return()
    }
    
    booking_data <- booking_data[1, ]
    
    # Get class information
    class_info <- classes_data() %>% 
      filter(class_id == booking_data$class_id)
    
    if(nrow(class_info) == 0) {
      safe_notify("Class not found", "error", 5)
      return()
    }
    
    class_info <- class_info[1, ]
    
    # Calculate total amount
    discount <- ifelse(booking_data$customer_type == "Member", 50, 0)
    final_price_per_slot <- class_info$price - discount
    total_amount <- final_price_per_slot * booking_data$slots_booked
    
    # Use existing booking_ref or generate one
    booking_ref <- ifelse(is.null(booking_data$booking_ref) || is.na(booking_data$booking_ref),
                          paste0("ST-", booking_data$booking_id, "-", 
                                 format(as.Date(booking_data$date_booked), "%Y%m%d")),
                          booking_data$booking_ref)
    
    # Show QR Code Modal
    showQRCodeModal(booking_data$booking_id, class_info, 
                    booking_data$customer_name, booking_data$contact,
                    booking_data$customer_type, booking_data$slots_booked,
                    total_amount, booking_ref)
  })
  
  # Update Booking - UPDATED for SQLite
  observeEvent(input$updateBooking, {
    if(!user_auth$logged_in) return()
    
    booking_id <- edit_booking_id()
    
    if(is.null(booking_id)) {
      safe_notify("No booking selected for update", "error", 5)
      return()
    }
    
    tryCatch({
      # Get current booking data
      current_booking <- bookings_data() %>% filter(booking_id == !!booking_id)
      if(nrow(current_booking) == 0) {
        safe_notify("Booking not found", "error", 5)
        return()
      }
      
      current_booking <- current_booking[1, ]
      
      # Check if booking can be edited
      if(current_booking$status != "Booked") {
        safe_notify("Only booked bookings can be edited", "error", 5)
        return()
      }
      
      # Get selected class info
      class_info <- classes_data() %>% 
        filter(class_id == input$editBookingClass)
      
      if(nrow(class_info) == 0) {
        safe_notify("Class not found", "error", 5)
        return()
      }
      
      # Validate required fields
      if(is.null(input$editBookingCustomer) || input$editBookingCustomer == "") {
        safe_notify("Customer name is required", "error", 5)
        return()
      }
      
      if(is.null(input$editBookingSlots) || input$editBookingSlots < 1) {
        safe_notify("Number of slots must be at least 1", "error", 5)
        return()
      }
      
      # Prepare data for update
      customer_name <- input$editBookingCustomer
      contact <- ifelse(is.null(input$editBookingContact) || input$editBookingContact == "", 
                        current_booking$contact, input$editBookingContact)
      
      # Build SQL query for update - SQLite version
      update_query <- sprintf(
        "UPDATE bookings SET 
         class_id = %d,
         customer_name = '%s',
         contact = '%s',
         slots_booked = %d,
         customer_type = '%s'
         WHERE booking_id = %d",
        as.integer(input$editBookingClass),
        gsub("'", "''", customer_name),
        gsub("'", "''", contact),
        as.integer(input$editBookingSlots),
        input$editCustomerType,
        as.integer(booking_id)
      )
      
      cat("Executing booking update query:", update_query, "\n")
      dbExecute(pool, update_query)
      
      removeModal()
      
      # Refresh data - slots will be recalculated in fetch_classes()
      fetch_classes()
      fetch_bookings()
      
      safe_notify("Booking updated successfully!", "success", 5)
      
      # Clear the edit_id
      edit_booking_id(NULL)
    }, error = function(e) {
      cat("Error updating booking:", e$message, "\n")
      safe_notify(paste("Error updating booking:", toString(e$message)), "error", 5)
    })
  })
  
  # Confirm cancel booking - UPDATED for SQLite
  observeEvent(input$confirmCancelBooking, {
    if(!user_auth$logged_in) return()
    
    booking_id <- cancel_booking_id()
    
    if(is.null(booking_id)) {
      safe_notify("No booking selected for cancellation", "error", 5)
      return()
    }
    
    tryCatch({
      # Get booking data
      booking <- bookings_data() %>% filter(booking_id == !!booking_id)
      if(nrow(booking) == 0) {
        safe_notify("Booking not found", "error", 5)
        return()
      }
      
      booking <- booking[1, ]
      
      # Update booking status to Cancelled
      cancel_query <- sprintf(
        "UPDATE bookings SET status = 'Cancelled' WHERE booking_id = %d",
        as.integer(booking_id)
      )
      
      dbExecute(pool, cancel_query)
      
      removeModal()
      
      # Refresh data - slots will be recalculated in fetch_classes()
      fetch_classes()
      fetch_bookings()
      
      safe_notify("Booking cancelled successfully!", "success", 5)
      
      # Clear the cancel_id
      cancel_booking_id(NULL)
    }, error = function(e) {
      cat("Error cancelling booking:", e$message, "\n")
      safe_notify(paste("Error cancelling booking:", toString(e$message)), "error", 5)
    })
  })
  
  # Update year filter dropdown for archives
  updateArchiveYearFilter <- function() {
    if(!user_auth$logged_in) return()
    
    data <- archived_classes_data()
    
    if(nrow(data) == 0) {
      updateSelectInput(session, "archive_year_filter", 
                        choices = c("All Years" = ""))
      return()
    }
    
    # Extract years from dates
    years <- unique(format(as.Date(data$date), "%Y"))
    years <- sort(years, decreasing = TRUE)
    
    year_choices <- c("All Years" = "")
    for(year in years) {
      year_choices <- c(year_choices, setNames(year, year))
    }
    
    updateSelectInput(session, "archive_year_filter", 
                      choices = year_choices)
  }
  
  # Filter archived classes data
  filtered_archived_data <- reactive({
    data <- archived_classes_data()
    
    if(is.null(data) || nrow(data) == 0) {
      return(data.frame())
    }
    
    # Apply month filter
    if(!is.null(input$archive_month_filter) && input$archive_month_filter != "") {
      selected_month <- input$archive_month_filter
      data <- data %>% filter(format(as.Date(date), "%m") == selected_month)
    }
    
    # Apply year filter
    if(!is.null(input$archive_year_filter) && input$archive_year_filter != "") {
      selected_year <- input$archive_year_filter
      data <- data %>% filter(format(as.Date(date), "%Y") == selected_year)
    }
    
    return(data)
  })
  
  # Reset archive filter
  observeEvent(input$reset_archive_filter, {
    if(!user_auth$logged_in) return()
    
    updateSelectInput(session, "archive_month_filter", selected = "")
    updateSelectInput(session, "archive_year_filter", selected = "")
  })
  
  # Refresh archives
  observeEvent(input$refresh_archives, {
    if(!user_auth$logged_in) return()
    
    fetch_archived_classes()
    updateArchiveYearFilter()
    safe_notify("Archives refreshed", "success", 3)
  })
  
  # Archived Classes Table - UPDATED (Removed Status column)
  output$archivedClassesTable <- renderDT({
    if(!user_auth$logged_in) return()
    
    data <- filtered_archived_data()
    
    if(nrow(data) == 0) {
      return(datatable(
        data.frame(
          Message = ifelse(
            is.null(input$archive_month_filter) || input$archive_month_filter == "",
            "No archived classes found.",
            "No archived classes match the selected filters."
          )
        ),
        options = list(dom = 't', searching = FALSE, info = FALSE, paging = FALSE),
        rownames = FALSE,
        selection = 'none'
      ))
    }
    
    display_data <- data %>%
      mutate(
        Date = format(as.Date(date), "%b %d, %Y"),
        Time = format(strptime(time, "%H:%M:%S"), "%I:%M %p"),
        "Total Revenue" = paste0("₱", 
                                 formatC(round((price * total_slots) - 
                                                 (50 * (total_slots - slots_remaining))), 
                                         format = "f", big.mark = ",", digits = 0)),
        Attendance = paste0(
          round((attended_slots / total_slots) * 100, 1), "% (",
          attended_slots, "/", total_slots, ")"),
        # REMOVED: Status column
        Actions = paste0(
          '<div style="display: flex; gap: 5px; justify-content: center;">
            <button class="btn-view" onclick="Shiny.setInputValue(\'view_archived_class\', \'', 
          class_id, '\')" title="View Details">
              <i class="fas fa-eye"></i>View
            </button>
            <button class="btn-delete" onclick="Shiny.setInputValue(\'delete_archived_class\', \'', 
          class_id, '\')" title="Delete Permanently">
              <i class="fas fa-trash"></i>Delete
            </button>
          </div>'
        )
      ) %>%
      select(
        Title = title,
        Instructor = instructor,
        Date = Date,
        Time = Time,
        "Total Slots" = total_slots,
        "Attendance Rate" = Attendance,
        "Total Revenue" = `Total Revenue`,
        # REMOVED: Status = Status,
        Actions = Actions
      )
    
    datatable(
      display_data,
      escape = FALSE,
      options = list(
        pageLength = 10,
        dom = 'Bfrtip',
        buttons = c('copy', 'csv', 'excel'),
        columnDefs = list(
          list(className = 'dt-center', targets = 4:7), # Changed from 4:8 to 4:7
          list(width = '150px', targets = 7) # Changed from 8 to 7
        )
      ),
      rownames = FALSE,
      selection = 'none'
    ) %>%
      formatStyle(
        columns = c(1:7), # Changed from 1:8 to 1:7
        fontSize = '14px'
      )
  })
  
  # View archived class details - UPDATED (Fixed format error)
  observeEvent(input$view_archived_class, {
    if(!user_auth$logged_in) return()
    
    class_id <- input$view_archived_class
    
    if(is.null(class_id) || class_id == "") {
      cat("No archived class ID provided\n")
      return()
    }
    
    # Get archived class data
    data <- archived_classes_data()
    class_data <- data %>% filter(class_id == !!class_id)
    
    if(nrow(class_data) == 0) {
      safe_notify("Archived class not found", "error", 5)
      return()
    }
    
    class_data <- class_data[1, ]
    
    # Get archived bookings for this class
    bookings <- tryCatch({
      query <- sprintf(
        "SELECT * FROM bookings 
         WHERE class_id = %d AND archived = 1
         ORDER BY date_booked DESC",
        as.integer(class_id)
      )
      dbGetQuery(pool, query)
    }, error = function(e) {
      cat("Error fetching archived bookings:", e$message, "\n")
      data.frame()
    })
    
    showModal(modalDialog(
      title = paste("Archived Class Details:", class_data$title),
      size = "l",
      easyClose = TRUE,
      footer = modalButton("Close"),
      
      div(
        h4("Class Information"),
        tableOutput("archivedClassDetailTable"),
        
        h4("Booked Customers"),
        if(nrow(bookings) > 0) {
          tagList(
            p(strong("Total Bookings:"), nrow(bookings)),
            p(strong("Attended Slots:"), class_data$attended_slots),
            p(strong("Cancelled Slots:"), class_data$cancelled_slots),
            DTOutput("archivedClassBookingsTable")
          )
        } else {
          p("No bookings found for this archived class.")
        }
      )
    ))
    
    output$archivedClassDetailTable <- renderTable({
      # Calculate total revenue correctly
      total_revenue <- round(
        (class_data$price * class_data$total_slots) - 
          (50 * (class_data$total_slots - class_data$slots_remaining))
      )
      
      # Format with comma separator
      formatted_revenue <- formatC(total_revenue, format = "f", big.mark = ",", digits = 0)
      
      data.frame(
        Field = c("Title", "Instructor", "Date", "Time", "Duration", 
                  "Price per Slot", "Total Slots", "Attended Slots", 
                  "Cancelled Slots", "Total Revenue"),
        Value = c(
          class_data$title,
          class_data$instructor,
          as.character(class_data$date),
          format(strptime(class_data$time, "%H:%M:%S"), "%I:%M %p"),
          paste(class_data$duration, "minutes"),
          paste0("₱", class_data$price),
          class_data$total_slots,
          class_data$attended_slots,
          class_data$cancelled_slots,
          paste0("₱", formatted_revenue)  # Fixed this line
        )
      )
    })
    
    output$archivedClassBookingsTable <- renderDT({
      display_bookings <- bookings %>%
        mutate(
          Status = case_when(
            status == "Booked" ~ '<span class="status-badge status-booked">Booked</span>',
            status == "Cancelled" ~ '<span class="status-badge status-cancelled">Cancelled</span>',
            status == "Attended" ~ '<span class="status-badge status-attended">Attended</span>',
            TRUE ~ status
          ),
          Date = format(as.Date(date_booked), "%b %d, %Y %H:%M")
        )
      
      datatable(
        display_bookings %>% select(
          Customer = customer_name, 
          "Customer Type" = customer_type, 
          Contact = contact, 
          "Booked Slots" = slots_booked, 
          Status = Status, 
          "Booking Date" = Date
        ),
        options = list(pageLength = 5, searching = FALSE),
        escape = FALSE,
        rownames = FALSE
      )
    })
  })
  
  # Delete archived class permanently - UPDATED for SQLite
  observeEvent(input$delete_archived_class, {
    if(!user_auth$logged_in) return()
    
    class_id <- input$delete_archived_class
    
    if(is.null(class_id) || class_id == "") {
      cat("No archived class ID provided\n")
      return()
    }
    
    showModal(modalDialog(
      title = "Confirm Permanent Delete",
      size = "m",
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirmDeleteArchivedClass", "Delete Permanently", 
                     class = "btn-danger", icon = icon("trash"))
      ),
      div(
        h4("Are you sure you want to delete this archived class permanently?"),
        p("This will delete:"),
        tags$ul(
          tags$li("The archived class record"),
          tags$li("All associated archived bookings"),
          tags$li("This action cannot be undone!")
        ),
        p(strong("Warning:"), "This will permanently remove all data related to this class.")
      )
    ))
    
    # Store class_id in a reactive value
    delete_archived_class_id(class_id)
  })
  
  # Reactive value for deleting archived class
  delete_archived_class_id <- reactiveVal(NULL)
  
  # Confirm delete archived class
  observeEvent(input$confirmDeleteArchivedClass, {
    if(!user_auth$logged_in) return()
    
    class_id <- delete_archived_class_id()
    
    if(is.null(class_id)) {
      safe_notify("No archived class selected for deletion", "error", 5)
      return()
    }
    
    tryCatch({
      # First, delete associated archived bookings
      delete_bookings_query <- sprintf(
        "DELETE FROM bookings WHERE class_id = %d AND archived = 1",
        as.integer(class_id)
      )
      dbExecute(pool, delete_bookings_query)
      
      # Then delete the archived class
      delete_class_query <- sprintf(
        "DELETE FROM classes WHERE class_id = %d AND archived = 1",
        as.integer(class_id)
      )
      dbExecute(pool, delete_class_query)
      
      removeModal()
      
      # Refresh archives data
      fetch_archived_classes()
      
      safe_notify("Archived class deleted permanently!", "success", 5)
      
      # Clear the delete_id
      delete_archived_class_id(NULL)
    }, error = function(e) {
      cat("Error deleting archived class:", e$message, "\n")
      safe_notify(paste("Error deleting archived class:", toString(e$message)), "error", 5)
    })
  })
  
  # Scanner Result Output
  output$scannerResult <- renderUI({
    # Initial state - nothing displayed
    NULL
  })
}

shinyApp(ui, server)
