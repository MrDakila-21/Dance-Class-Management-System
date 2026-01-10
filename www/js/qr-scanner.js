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
    // Don't show error if scanner was intentionally stopped
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