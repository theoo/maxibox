#!/usr/bin/env ruby
# -*- ruby encoding: utf-8 -*-

require 'yaml'
require 'time'

require 'tinkerforge/ip_connection'
require 'tinkerforge/brick_master'
require 'tinkerforge/bricklet_nfc'
require 'tinkerforge/bricklet_rotary_encoder_v2'
require 'tinkerforge/bricklet_dual_button'
require 'tinkerforge/bricklet_temperature'
include Tinkerforge

require 'audite'

FAIL_SOUND_NAME = "fail.mp3"
SUCCESS_SOUND_NAME = "success.mp3"

class Sensors
  
  attr_reader :nfc_status,
    :buttons,
    :buttons_counters,
    :encoder_button_status,
    :encoder
  
  attr_accessor :connection

  def initialize(settings)
    @secret = settings['secret']

    @nfc_status = {state: 'pending'}
    
    @buttons = {
      right: false,
      left: false
    }
    @buttons_counters = {
      right: 0,
      left: 0
    }

    @encoder = 0
    @encoder_button_status = false
    @encoder_last_press_time = Time.now

    @connection = IPConnection.new
    @connection.set_auto_reconnect false

    @master_brick = BrickMaster.new settings['uids']['master_uid'], @connection
    @nfc_bricklet = BrickletNFC.new settings['uids']['nfc_uid'], @connection
    @encoder_bricklet = BrickletRotaryEncoderV2.new settings['uids']['encorder_uid'], @connection
    @buttons_bricklet = BrickletDualButton.new settings['uids']['buttons_uid'], @connection
    @temperature_bricklet = BrickletTemperature.new settings['uids']['temperature_uid'], @connection

    boot
    @connection.connect settings['host'], settings['port']
    self
  end

  def encoder_button_pressed_seconds
    @encoder_button_status ? Time.now - @encoder_last_press_time : 0
  end

  def request_reading
    @nfc_bricklet.set_mode BrickletNFC::MODE_READER
  end

  def set_leds(left, right)
    @buttons_bricklet.set_led_state(left, right)
  end

  def reset_buttons_counters
    @buttons_counters = {
      right: 0,
      left: 0
    }
  end

  def connected?
    @connection.get_connection_state == IPConnection::CONNECTION_STATE_CONNECTED
  end

  def close
    @connection.disconnect
  end

  private 
    
    def boot

      @connection.register_callback(IPConnection::CALLBACK_CONNECTED) do |connect_reason|
        case connect_reason
          when IPConnection::CONNECT_REASON_REQUEST
            puts 'Connected by request'
          when IPConnection::CONNECT_REASON_AUTO_RECONNECT
            puts 'Auto-Reconnect'
        end

        # Authenticate first...
        begin
          @connection.authenticate @secret

          # ...reenable auto reconnect mechanism, as described above...
          @connection.set_auto_reconnect true

          @connection.enumerate
          @temperature_bricklet.set_temperature_callback_period 1000
          @encoder_bricklet.set_count_callback_configuration 1000, false, 'x', 0, 0
          # nfc_bricklet.set_response_expected_all
          @nfc_bricklet.set_mode BrickletNFC::MODE_READER
          @buttons_bricklet.set_selected_led_state(BrickletDualButton::LED_LEFT, 
            BrickletDualButton::LED_STATE_AUTO_TOGGLE_OFF)
          @buttons_bricklet.set_selected_led_state(BrickletDualButton::LED_RIGHT, 
            BrickletDualButton::LED_STATE_AUTO_TOGGLE_OFF)

          puts 'Authentication succeeded'
        rescue Exception => e
          puts 'Could not authenticate'
          puts e.message
        end
      end

      @connection.register_callback(IPConnection::CALLBACK_ENUMERATE) do |uid, connected_uid, position,
                                                                    hardware_version, firmware_version,
                                                                    device_identifier, enumeration_type|

        puts "UID: #{uid}, Enumeration Type: #{enumeration_type}"

        # Get current stack voltage
        stack_voltage = @master_brick.get_stack_voltage
        puts "Stack Voltage: #{stack_voltage/1000.0} V"
        
        # Get current stack current
        stack_current = @master_brick.get_stack_current
        puts "Stack Current: #{stack_current/1000.0} A"

      end

      @nfc_bricklet.register_callback(BrickletNFC::CALLBACK_READER_STATE_CHANGED) do |state, idle|
        begin
          if state == BrickletNFC::READER_STATE_IDLE
            @nfc_bricklet.reader_request_tag_id
            @nfc_status = {state: 'pending'}
          elsif state == BrickletNFC::READER_STATE_REQUEST_TAG_ID_READY
            tag_id = Array.new
            ret = @nfc_bricklet.reader_get_tag_id

            ret[1].each do |v|
              tag_id.push "%X" % v
            end

            @nfc_status = {state: 'success', data: tag_id.join("")}
          elsif state == BrickletNFC::READER_STATE_REQUEST_TAG_ID_ERROR
            @nfc_status = {state: 'absent'}
          end
        rescue Exception => e
          @nfc_status = {state: 'fail'}
          puts e.message
        end
      end

      @temperature_bricklet.register_callback(BrickletTemperature::CALLBACK_TEMPERATURE) do |temperature|
        puts "Temperature: #{temperature/100.0} °C"
      end

      @encoder_bricklet.register_callback(BrickletRotaryEncoderV2::CALLBACK_COUNT) do |count|
        @encoder = count
      end
      @encoder_bricklet.register_callback(BrickletRotaryEncoderV2::CALLBACK_PRESSED) do
        @encoder_button_status = true
        @encoder_last_press_time = Time.now if @encoder_bricklet.is_pressed
      end
      @encoder_bricklet.register_callback(BrickletRotaryEncoderV2::CALLBACK_RELEASED) do
        @encoder_button_status = false
      end

      @buttons_bricklet.register_callback(BrickletDualButton::CALLBACK_STATE_CHANGED) do |button_l, button_r,
                                                                                       led_l, led_r|
        if button_l == BrickletDualButton::BUTTON_STATE_PRESSED
          @buttons[:left] = true
        elsif button_l == BrickletDualButton::BUTTON_STATE_RELEASED
          @buttons_counters[:left] += 1
          @buttons[:left] = false
          set_leds(0, 0)
        end

        if button_r == BrickletDualButton::BUTTON_STATE_PRESSED
          @buttons[:right] = true
        elsif button_r == BrickletDualButton::BUTTON_STATE_RELEASED
          @buttons_counters[:right] += 1
          @buttons[:right] = false
          set_leds(0, 0)
        end

      end

    end

end

class NfcSound

  attr_reader :songs

  def initialize(mapping_file_path, songs_folder_path)
    @mapping = {}
    @mapping_file_path = mapping_file_path
    @songs_folder_path = songs_folder_path
    @songs = scan_songs_folder
    @current_song_index = 0
    load
  end

  def load
    @mapping = YAML::load_file(@mapping_file_path) 
    @mapping = {} unless @mapping
  end

  def save
    File.open(@mapping_file_path, 'w') do |f|
      f.write @mapping.to_yaml
    end 
  end

  def set_song_for(tag_id, song_name)
    @mapping[tag_id] = template if not @mapping[tag_id]
    list = @mapping[tag_id][:songs_list]
    list.push(song_name)
    @mapping[tag_id][:songs_list] = list.uniq
    save
  end

  def get_songs_for(tag_id)
    @mapping[tag_id] ? @mapping[tag_id][:songs_list] : []
  end

  def fail_song
    full_path_for(FAIL_SOUND_NAME)
  end

  def success_song
    full_path_for(SUCCESS_SOUND_NAME)
  end

  def seek(idx)
    @current_song_index = (@current_song_index + idx) % @songs.length
    @songs[@current_song_index]
  end

  def full_path_for(song)
    [@songs_folder_path, song].join("/")
  end

  private


  def base_name_for(path)
    File.basename path
  end

  def scan_songs_folder
    all = Dir.glob("#{@songs_folder_path}/*.mp3")
    all.delete(fail_song)
    all.delete(success_song)
    all
  end

  def template
    {
      songs_list: [],
      last_song_played: "",
      last_position: ""
    }
  end

end

class Player < Audite

  def play(file, queue = true)

    if @active and queue
      # puts "#{position.ceil} / #{length_in_seconds.ceil}"
      if File.basename(file) != current_song_name and not @song_list.map(&:file).include?(file)
        puts "Queuing new file #{file}"
        queue file
      end
    else
      stop_stream
      load(file)
      start_stream
      puts "Playing '#{current_song_name}'"
    end

  end

  def stop
    if @active
      puts "Stopping playback."
      stop_stream
    end
  end

end