const canvasContainer = document.getElementById("canvas-container")
const imageUpload = document.getElementById("imageUpload")
const colorPicker = document.getElementById("colorPicker")

let width, height
let rotate = false

let pixels = [] // Stores the color of each pixel
let isDrawing = false
let activeWall = false
let currentColor = colorPicker.value
let originalOverflow

function setGrid(h, w, r) {
  width = w
  height = h
  rotate = r
}

// Initialize the pixel grid
function createGrid() {
  const rows = height
  const cols = width
  canvasContainer.innerHTML = "" // Clear previous grid
  canvasContainer.style.gridTemplateColumns = `repeat(${cols}, 1fr)`
  canvasContainer.style.gridTemplateRows = `repeat(${rows}, 1fr)`
  pixels = []

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const pixel = document.createElement("div")
      pixel.classList.add("pixel")
      pixel.dataset.x = x
      pixel.dataset.y = y
      pixel.style.backgroundColor = "#000000" // Default black
      canvasContainer.appendChild(pixel)
    }
  }
}

function startDrawing(e) {
  isDrawing = true
  originalOverflow = document.documentElement.style.overflow
  document.documentElement.style.overflow = "hidden"

  // Handle single-pixel touch/click
  if (e.target.classList.contains("pixel")) {
    e.target.style.backgroundColor = currentColor
  }
}

const continueDrawing = (e) => {
  if (!isDrawing) return

  // Use `e.target` for mouse events
  if (e.type === "mousemove" && e.target.classList.contains("pixel")) {
    e.target.style.backgroundColor = currentColor
  }

  // For touch events, find the element at the touch coordinates
  if (e.type === "touchmove") {
    const touch = e.touches[0]
    const targetElement = document.elementFromPoint(touch.clientX, touch.clientY)
    if (targetElement && targetElement.classList.contains("pixel")) {
      targetElement.style.backgroundColor = currentColor
    }
    e.preventDefault() // Prevent scrolling
  }
}

function stopDrawing() {
  isDrawing = false
  document.documentElement.style.overflow = originalOverflow
}

const updateColor = (e) => {
  currentColor = e.target.value
}

// Mouse events
canvasContainer.addEventListener("mousedown", startDrawing)
window.addEventListener("mouseup", stopDrawing)
canvasContainer.addEventListener("mouseleave", stopDrawing)
canvasContainer.addEventListener("mousemove", continueDrawing)

// Touch events
canvasContainer.addEventListener("touchstart", startDrawing, { passive: false })
window.addEventListener("touchend", stopDrawing)
canvasContainer.addEventListener("touchcancel", stopDrawing)
canvasContainer.addEventListener("touchmove", continueDrawing, { passive: false })

// Other controls
colorPicker.addEventListener("change", updateColor)

// load image and pixelate to canvas grid size
function loadPixels(evt) {
  const file = imageUpload.files[0]
  if (!file) {
    alert("Please select an image to upload.")
    return
  }

  const reader = new FileReader()
  reader.onload = function (e) {
    const img = new Image()
    img.onload = function () {
      const tempCanvas = document.createElement("canvas")
      const ctx = tempCanvas.getContext("2d")

      const scale = width / img.height; // how much to scale the image to fit
      tempCanvas.width = width;
      tempCanvas.height = height;
      ctx.setTransform(
        0, scale, // x axis down the screen
        -scale, 0, // y axis across the screen from right to left
        width,    // x origin is on the right side of the canvas
        0         // y origin is at the top
      );
      ctx.drawImage(img, 0, 0);
      ctx.setTransform(1, 0, 0, 1, 0, 0); // restore default

      const imageData = ctx.getImageData(0, 0, width, height).data

      // Recreate grid based on image dimensions
      createGrid(Math.round(height), Math.round(width))

      for (let i = 0; i < imageData.length; i += 4) {
        const r = imageData[i]
        const g = imageData[i + 1]
        const b = imageData[i + 2]
        const hexColor = `#${r.toString(16).padStart(2, "0")}${g.toString(16).padStart(2, "0")}${b.toString(16).padStart(2, "0")}`
        const pixelIndex = i / 4
        const pixelElement = canvasContainer.children[pixelIndex]
        if (pixelElement) {
          pixelElement.style.backgroundColor = hexColor
          pixels[pixelIndex] = hexColor
        }
      }
    }
    img.src = e.target.result
  }
  reader.readAsDataURL(file)
}

function sendImage(evt) {
  console.log("sending image")
  const tempCanvas = document.createElement("canvas")
  tempCanvas.width = width
  tempCanvas.height = height
  const ctx = tempCanvas.getContext("2d")

  document.querySelectorAll(".pixel").forEach((pixel, index) => {
    const x = index % width
    const y = Math.floor(index / width)
    const color =
      pixel.style.backgroundColor === "rgb(238, 238, 238)"
        ? "#eee"
        : pixel.style.backgroundColor // Default to light gray if not explicitly colored
    ctx.fillStyle = color
    ctx.fillRect(x, y, 1, 1)
  })

  const bytes = getRawBytes(tempCanvas)
  uploadRawPngBytes(bytes)
}

function getRawBytes(canvas) {
  const ctx = canvas.getContext("2d")
  const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height)
  const rgbaData = imageData.data // Uint8ClampedArray (R, G, B, A for each pixel) starting top left
  return rgbaData
}

async function uploadRawPngBytes(bytes) {
  try {
    const res = await fetch("/uploadRawImg", {
      method: "POST",
      headers: {
        "Content-Type": "image/png",
      },
      body: bytes, // Send the raw bytes directly
    })
    if (res.ok) {
      console.log("PNG uploaded successfully!")
    } else {
      console.error("Failed to upload PNG:", res.statusText)
    }
  } catch (err) {
    console.log(err)
  }
}

async function toggleActive() {
  try {
    const res = await fetch("/toggleActive", { method: "PUT" })
    if (res.ok) {
      console.log("Toggled successfully!")
      activeWall = !activeWall
      if (activeWall) {
        document.getElementById("toggleButton").classList.add("active")
        document.getElementById("toggleButton").innerText = "Stopp"
      } else {
        document.getElementById("toggleButton").classList.remove("active")
        document.getElementById("toggleButton").innerText = "Kjør"
      }
    } else {
      console.error("Failed to toggle active: ", res.statusText)
    }
  } catch (err) {
    console.log(err)
  }
}

async function start() {
  try {
    const res = await fetch("/start", { method: "PUT" })
    if (res.ok) {
      console.log("started successfully!")
    } else {
      console.error("Failed to start wall: ", res.statusText)
    }
  } catch (err) {
    console.log(err)
  }
}

function download(evt) {
  const tempCanvas = document.createElement("canvas")
  tempCanvas.width = width
  tempCanvas.height = height
  const ctx = tempCanvas.getContext("2d")

  document.querySelectorAll(".pixel").forEach((pixel, index) => {
    const x = index % width
    const y = Math.floor(index / width)
    const color =
      pixel.style.backgroundColor === "rgb(238, 238, 238)"
        ? "#eee"
        : pixel.style.backgroundColor // Default to light gray if not explicitly colored
    ctx.fillStyle = color
    ctx.fillRect(x, y, 1, 1)
  })

  const link = document.createElement("a")
  link.download = "pixel_art.png"
  link.href = tempCanvas.toDataURL("image/png")
  link.click()
}

function clearCanvas() {
  createGrid() // Re-initialize with default white pixels
}

export { setGrid, createGrid, loadPixels, clearCanvas, download, sendImage, toggleActive, start }
