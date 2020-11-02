#!/usr/bin/env ruby
# -*- ruby encoding: utf-8 -*-

require_relative 'snd-maxi'
require 'time'
require 'yaml'

SETTINGS = YAML::load_file("settings.yml")

########################################################################################################################

player = Player.new
mapping = NfcSound.new(SETTINGS['mapping_file'], SETTINGS['songs_folder_path'])
sensors = Sensors.new(SETTINGS['tinkerforge'])
mode = :read
volume_mid_point = (SETTINGS['max_volume'] + SETTINGS['min_volume']) / 2
last_volume = volume_mid_point

begin

  loop do

    if sensors.connected?

      if sensors.nfc_status[:state] == 'success'
        tag_id = sensors.nfc_status[:data]

        if mode == :scan
          
          if sensors.encoder_button_pressed_seconds > SETTINGS['encoder_button_setup_delay'] 
            puts "Recording a new chip."
            mapping.set_song_for(tag_id, player.current_song_name)
            player.play(mapping.success_song, false)
            mode = :read
            while sensors.encoder_button_status
              puts "Waiting until button is release."
              sleep 1
            end
            sensors.reset_buttons_counters
          end

        else

          songs = mapping.get_songs_for(tag_id)

          if songs.length > 0
            current_song = player.active ? player.current_song_name : nil
            if not player.active or not songs.include?(current_song)
              # TODO: if file is not found, remove from mapping and continuer (play fail song)
              player.play(mapping.full_path_for(songs.sample), false)
            end
            sensors.set_leds(0, 0)
          elsif not sensors.encoder_button_status
            puts "Chip not recognized."
            if player.active and player.current_song_name != File.basename(mapping.fail_song)
              player.stop 
            end
            sensors.set_leds(1, 1)
            player.play(mapping.fail_song)
          end

        end

        sensors.request_reading
      
      elsif sensors.nfc_status[:state] == 'absent' and mode == :read

        player.stop
        sensors.set_leds(1, 1)
        sensors.request_reading
        
      end

      if sensors.buttons[:right] and sensors.buttons[:left] and mode == :read
        puts "Starting scan mode. Queued files are:"
        mapping.songs.each do |s|
          puts "- #{s}"
        end
        player.play(mapping.songs[0], false)
        mode = :scan
        sleep 1 # wait for user to release both buttons
        sensors.reset_buttons_counters
      end

      if mode == :scan

        # next
        if sensors.buttons_counters[:right] > 0
          sleep 0.5
          player.play(mapping.seek(1), false)
          sensors.reset_buttons_counters
          sensors.request_reading
        end
        
        # previous
        if sensors.buttons_counters[:left] > 0
          sleep 0.5
          player.play(mapping.seek(-1), false)
          sensors.reset_buttons_counters
          sensors.request_reading
        end

      end

      if sensors.encoder != 0
        # current_volume = `amixer get Master | grep -E "\[[0-9]+%\]" | awk -F"[]%[]" '{ print $2 }'`
        
        target_volume = volume_mid_point + sensors.encoder
        target_volume = SETTINGS['min_volume'] if target_volume < SETTINGS['min_volume']
        target_volume = SETTINGS['max_volume'] if SETTINGS['max_volume'] < target_volume

        if last_volume != target_volume
          puts "Set volume to #{target_volume}%"
          `amixer set Master #{target_volume}%`
          last_volume = target_volume
        end
      end

    end

    sleep 0.1
  end

rescue SystemExit, Interrupt
  puts "Exiting..."
  player.close
  sensors.close
  exit
rescue Exception => e
  raise e
end


