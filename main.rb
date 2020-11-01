#!/usr/bin/env ruby
# -*- ruby encoding: utf-8 -*-

require './snd-maxi'
require 'time'

MAPPING_FILE = "./mapping.yml"
SONGS_FOLDER_PATH = "./songs"

HOST = 'snd-maxi'
PORT = 4223

UIDS = {
  MASTER_UID:  '6R4ZSS',
  NFC_UID: 'Gub',
  ENCORDER_UID: 'EqK',
  BUTTONS_UID: 'vxG',
  TEMPERATURE_UID: '5RS'
}

SECRET = 'guess_what?'

ENCODER_BUTTON_SETUP_DELAY = 3

########################################################################################################################

player = Player.new
mapping = NfcSound.new(MAPPING_FILE, SONGS_FOLDER_PATH)
sensors = Sensors.new(UIDS, HOST, PORT, SECRET)
mode = :read

begin

  loop do

    if sensors.connected?

      if sensors.nfc_status[:state] == 'success'
        tag_id = sensors.nfc_status[:data]

        if mode == :scan
          
          if sensors.encoder_button_pressed_seconds > ENCODER_BUTTON_SETUP_DELAY 
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
            player.play(songs.sample)
            sensors.set_leds(0, 0)
          elsif not sensors.encoder_button_status
            puts "Chip not recognized."
            player.play(mapping.fail_song)
          end

        end

        sensors.request_reading
      
      elsif sensors.nfc_status[:state] == 'absent' and mode == :read

        if player.active
          puts "Stopping playback."
          player.stop_stream
          sensors.set_leds(1, 1)
        end

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


