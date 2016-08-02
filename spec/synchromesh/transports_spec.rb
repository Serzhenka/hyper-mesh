require 'spec_helper'
require 'synchromesh/test_components'


SKIP_MESSAGE = 'Pusher credentials not specified. '\
 'To run set env variable PUSHER=xxxx-yyy-zzz (app id - key - secret)'

def pusher_credentials
  Hash[*[:app_id, :key, :secret].zip(ENV['PUSHER'].split('-')).flatten]
rescue
  nil
end

describe "Transport Tests", js: true do

  before(:each) do
    5.times { |i| FactoryGirl.create(:test_model, test_attribute: "I am item #{i}") }
  end

  context "Simple Polling" do

    before(:all) do
      Synchromesh.configuration do |config|
        config.transport = :simple_poller
        # slow down the polling so wait_for_ajax works
        config.opts = { seconds_between_poll: 2 }
      end
    end

    it "receives change notifications" do
      mount "TestComponent"
      TestModel.new(test_attribute: "I'm new here!").save
      page.should have_content("6 items")
    end

    it "receives destroy notifications" do
      mount "TestComponent"
      TestModel.first.destroy
      page.should have_content("4 items")
    end

  end

  context "Real Pusher Account", skip: (pusher_credentials ? false : SKIP_MESSAGE) do

    before(:all) do
      require 'pusher'

      Object.send(:remove_const, :PusherFake) if defined?(PusherFake)

      Synchromesh.configuration do |config|
        config.transport = :pusher
        config.channel_prefix = "synchromesh"
        config.opts = pusher_credentials
      end
    end

    it "receives change notifications" do
      mount "TestComponent"
      TestModel.new(test_attribute: "I'm new here!").save
      page.should have_content("6 items")
    end

    it "receives destroy notifications" do
      mount "TestComponent"
      TestModel.first.destroy
      page.should have_content("4 items")
    end

  end
end