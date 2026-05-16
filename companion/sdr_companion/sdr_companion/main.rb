# frozen_string_literal: true

# SDR Companion — core implementation.
#
# Namespace: DSheb::SDRCompanion.
# File-IPC: reads /tmp/sdr_cmd.json, writes /tmp/sdr_result.json.
# Polls every POLL_INTERVAL seconds via UI.start_timer.
#
# Supported commands (JSON {"action": ..., "id": ..., ...}):
#   - {"action":"ping"}                                 → {"ok":true, "result":"pong"}
#   - {"action":"resize_viewport","w":1920,"h":1080}    → {"ok":true, "result":{vp_w, vp_h, window:{x,y,w,h}, viewport_in_window:{x,y,w,h}}}
#   - {"action":"get_window_bounds"}                    → {"ok":true, "result":{window:{...}, viewport:{...}, viewport_in_window:{...}}}
#   - {"action":"select_all"}                           → selects all top-level groups + instances
#   - {"action":"clear_selection"}
#
# `id` field is echoed back so the caller can match async responses.

require 'json'

module DSheb
  module SDRCompanion
    extend self

    CMD_PATH    = '/tmp/sdr_cmd.json'
    RESULT_PATH = '/tmp/sdr_result.json'

    POLL_INTERVAL = 0.2

    @timer       = nil
    @last_cmd_id = nil

    def install
      return if @timer
      @timer = UI.start_timer(POLL_INTERVAL, true) { tick }
      log("companion installed, polling #{CMD_PATH} every #{POLL_INTERVAL}s")
    rescue StandardError => e
      log("install error: #{e.message}")
    end

    def uninstall
      UI.stop_timer(@timer) if @timer
      @timer = nil
    end

    def tick
      return unless File.exist?(CMD_PATH)
      raw = File.read(CMD_PATH)
      return if raw.strip.empty?

      cmd = JSON.parse(raw)
      id = cmd['id'] || cmd[:id]

      # Skip if we've already handled this command id.
      if id && id == @last_cmd_id
        return
      end
      @last_cmd_id = id if id

      result = dispatch(cmd)
      write_result(id, true, result)
    rescue StandardError => e
      log("tick error: #{e.class}: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      write_result(@last_cmd_id, false, e.message)
    ensure
      # Caller is expected to bump `id` per command, so reading the same file
      # repeatedly is fine. We do NOT delete the file — caller manages lifecycle.
    end

    def dispatch(cmd)
      action = (cmd['action'] || cmd[:action]).to_s
      case action
      when 'ping'              then 'pong'
      when 'resize_viewport'   then handle_resize_viewport(cmd)
      when 'get_window_bounds' then bounds_payload
      when 'select_all'        then handle_select_all
      when 'clear_selection'   then handle_clear_selection
      else
        raise "unknown action: #{action.inspect}"
      end
    end

    def handle_resize_viewport(cmd)
      w = (cmd['w'] || cmd[:w]).to_i
      h = (cmd['h'] || cmd[:h]).to_i
      raise 'width and height must be positive' if w <= 0 || h <= 0
      raise 'SketchUp 2022.1+ required for resize_viewport' if Sketchup.version.to_f < 22.1

      Sketchup.resize_viewport(Sketchup.active_model, w, h)
      bounds_payload
    end

    def handle_select_all
      m = Sketchup.active_model
      m.selection.clear
      (m.entities.grep(Sketchup::Group) +
       m.entities.grep(Sketchup::ComponentInstance)).each { |e| m.selection.add(e) }
      { 'selected' => m.selection.length }
    end

    def handle_clear_selection
      Sketchup.active_model.selection.clear
      { 'selected' => 0 }
    end

    # Returns:
    #   {
    #     "window":            {x, y, w, h},  # SU window frame (top-left origin, points)
    #     "viewport":          {w, h},        # vpwidth, vpheight (model area size in points)
    #     "viewport_in_window":{x, y, w, h}   # model area offset INSIDE window
    #   }
    #
    # All coords in macOS logical points. Recorder converts to absolute screen
    # coords by adding window.{x,y} to viewport_in_window.{x,y}.
    #
    # SU does not directly expose the in-window offset of the viewport. We
    # estimate it via assumed chrome (title bar + top toolbar = ~70, status bar
    # ~25, sides 0). Verified empirically on SketchUp 2026 macOS. If chrome
    # changes (panels shown/hidden), recalibrate via the calibration tool.
    def bounds_payload
      v = Sketchup.active_model.active_view
      vp_w = v.vpwidth.to_i
      vp_h = v.vpheight.to_i
      win  = osx_window_frame || { 'x' => 0, 'y' => 0, 'w' => vp_w, 'h' => vp_h + 95 }

      # Default chrome offsets (overridden by calibration in Hammerspoon settings).
      offset_top    = 70
      offset_bottom = 25
      offset_left   = 0
      offset_right  = 0

      vp_in_win_w = win['w'] - offset_left - offset_right
      vp_in_win_h = win['h'] - offset_top  - offset_bottom

      {
        'window'             => win,
        'viewport'           => { 'w' => vp_w, 'h' => vp_h },
        'viewport_in_window' => {
          'x' => offset_left, 'y' => offset_top,
          'w' => vp_in_win_w, 'h' => vp_in_win_h
        }
      }
    end

    # SU Ruby API doesn't expose the host-app window frame directly.
    # We return nil here and let Hammerspoon use hs.window to get accurate bounds.
    # Stub kept for future native impl (e.g., via PlatformExt).
    def osx_window_frame
      nil
    end

    def write_result(id, ok, result)
      payload = { 'id' => id, 'ok' => ok, 'result' => result, 'ts' => Time.now.to_f }
      File.write(RESULT_PATH, JSON.generate(payload))
    rescue StandardError => e
      log("write_result error: #{e.message}")
    end

    def log(msg)
      File.open('/tmp/sdr_companion.log', 'a') { |f| f.puts("[#{Time.now}] #{msg}") }
    rescue StandardError
      # never let logging crash the plugin
    end

    unless @installed
      @installed = true
      install
    end
  end
end
