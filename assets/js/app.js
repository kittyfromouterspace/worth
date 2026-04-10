import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

let Hooks = {}

// Auto-scroll chat container when streaming, but only if user is near the bottom
Hooks.ChatScroll = {
  mounted() {
    this.userScrolledUp = false
    this.el.addEventListener("scroll", () => {
      const threshold = 150
      const distFromBottom = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight
      this.userScrolledUp = distFromBottom > threshold
    })
    this.handleEvent("scroll_to_bottom", () => {
      this.scrollToBottom()
    })

    // Watch for new stream items being inserted (LiveView streams don't trigger updated())
    this.observer = new MutationObserver(() => {
      if (!this.userScrolledUp) {
        this.scrollToBottom()
      }
    })
    const streamContainer = this.el.querySelector("[phx-update='stream']")
    if (streamContainer) {
      this.observer.observe(streamContainer, { childList: true })
    }

    this.scrollToBottom()
  },
  updated() {
    if (this.el.dataset.autoScroll === "true" && !this.userScrolledUp) {
      this.scrollToBottom()
    }
  },
  destroyed() {
    if (this.observer) this.observer.disconnect()
  },
  scrollToBottom() {
    requestAnimationFrame(() => {
      this.el.scrollTop = this.el.scrollHeight
      this.userScrolledUp = false
    })
  }
}

// Auto-focus and clear input after submit
// Command tree for Tab completion
const COMMANDS = [
  "/help", "/quit", "/clear", "/cost", "/status", "/settings",
  "/mode code", "/mode research", "/mode planned", "/mode turn_by_turn",
  "/workspace list", "/workspace new ", "/workspace switch ",
  "/memory query ", "/memory note ", "/memory recent", "/memory reembed",
  "/skill list", "/skill read ", "/skill remove ", "/skill history ", "/skill rollback ", "/skill refine ",
  "/session list", "/session resume ",
  "/mcp list", "/mcp connect ", "/mcp disconnect ", "/mcp tools ",
  "/kit search ", "/kit install ", "/kit list", "/kit info ",
  "/provider list", "/provider enable ", "/provider disable ",
  "/catalog refresh",
  "/usage", "/usage refresh",
  "/setup", "/setup openrouter ", "/setup embedding "
]

Hooks.InputFocus = {
  mounted() {
    this.el.focus()
    this.handleEvent("clear_input", () => {
      this.el.value = ""
      this.el.focus()
    })

    this.el.addEventListener("keydown", (e) => {
      if (e.key === "Tab") {
        e.preventDefault()
        const val = this.el.value
        if (!val.startsWith("/")) return

        const matches = COMMANDS.filter(c => c.startsWith(val) && c !== val)
        if (matches.length === 0) return

        if (matches.length === 1) {
          this.el.value = matches[0]
        } else {
          // Complete to longest common prefix
          let prefix = matches[0]
          for (const m of matches) {
            while (!m.startsWith(prefix)) {
              prefix = prefix.slice(0, -1)
            }
          }
          if (prefix.length > val.length) {
            this.el.value = prefix
          }
        }
        this.el.dispatchEvent(new Event("input", { bubbles: true }))
      }
    })
  },
  updated() {
    if (!this.el.disabled) {
      this.el.focus()
      this.el.value = ""
    }
  }
}

// Manages live theme switching — updates body class and theme <style> tag
Hooks.ThemeManager = {
  mounted() {
    this.handleEvent("apply_theme", ({bg_class, css}) => {
      // Update body class — remove all bg-* classes, apply new one
      const body = document.body
      const classes = [...body.classList].filter(c => c.startsWith("bg-"))
      classes.forEach(c => body.classList.remove(c))
      bg_class.split(" ").filter(Boolean).forEach(c => body.classList.add(c))

      // Update theme style tag
      const styleEl = document.getElementById("theme-css")
      if (styleEl) {
        styleEl.textContent = css
      }
    })
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#89b4fa"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Dev quality of life features
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    reloader.enableServerLogs()

    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
