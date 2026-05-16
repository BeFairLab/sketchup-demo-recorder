# frozen_string_literal: true

# SDR Companion — root registrar.
#
# Tiny companion plugin for sketchup-demo-recorder (Hammerspoon-based).
# Exposes file-IPC API for viewport resize + window bounds reporting.
#
# Extension Warehouse rule: this file MUST contain only the registration call;
# no logic, no file loading. The matching sdr_companion/ folder holds all code.

module DSheb
  module SDRCompanion
    EXTENSION = SketchupExtension.new('SDR Companion', 'sdr_companion/main')
    EXTENSION.creator     = 'Daniil Shebyakin'
    EXTENSION.description = 'File-IPC bridge for sketchup-demo-recorder. Resizes ' \
                            'the SketchUp viewport on command and reports window bounds.'
    EXTENSION.version     = '0.1.0'
    EXTENSION.copyright   = '2026 Daniil Shebyakin'
    Sketchup.register_extension(EXTENSION, true)
  end
end
