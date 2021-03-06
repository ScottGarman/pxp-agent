require 'pxp-agent/config_helper.rb'
require 'pxp-agent/test_helper.rb'

test_name 'C97964 - agent should use next broker if primary is timing out' do

  agents.each do |agent|
    if agent.platform =~ /^cisco_ios_xr/
      skip_test 'PCP-685: Skip Cisco XR Platform'
    end
  end

  PRIMARY_BROKER_INSTANCE = 0
  REPLICA_BROKER_INSTANCE = 1
  teardown do
    unblock_pcp_broker(master,PRIMARY_BROKER_INSTANCE)
    kill_all_pcp_brokers(master)
    run_pcp_broker(master,    PRIMARY_BROKER_INSTANCE)
  end

  step 'Ensure each agent host has pxp-agent configured with multiple uris, running and associated' do
    agents.each do |agent|
      on agent, puppet('resource service pxp-agent ensure=stopped')
      num_brokers = 2
      pxp_config = pxp_config_hash_using_puppet_certs(master, agent, num_brokers)
      pxp_config['allowed-keepalive-timeouts'] = 0
      create_remote_file(agent, pxp_agent_config_file(agent), pxp_config.to_json.to_s)
      retry_on(agent, "rm -rf #{logfile(agent)}")
      on agent, puppet('resource service pxp-agent ensure=running')
      show_pcp_logs_on_failure do
        assert_equal(master[:pcp_broker_instance], PRIMARY_BROKER_INSTANCE, "broker instance is not set correctly: #{master[:pcp_broker_instance]}")
        assert(is_associated?(master, "pcp://#{agent}/agent"),
               "Agent identity pcp://#{agent}/agent for agent host #{agent} does not appear in pcp-broker's (#{broker_ws_uri(master)}) client inventory after ~#{PCP_INVENTORY_RETRIES} seconds")
      end
    end
  end

  step 'Block primary broker, start replica' do
    block_pcp_broker(master,PRIMARY_BROKER_INSTANCE)
    run_pcp_broker(master,  REPLICA_BROKER_INSTANCE)
  end

  step 'On each agent, test that a new association has occurred' do
    assert_equal(master[:pcp_broker_instance], REPLICA_BROKER_INSTANCE, "broker instance is not set correctly: #{master[:pcp_broker_instance]}")
    agents.each do |agent|
      inventory_retries = 120
      assert(is_associated?(master, "pcp://#{agent}/agent", inventory_retries),
             "Agent identity pcp://#{agent}/agent for agent host #{agent} does not appear in pcp-broker's (#{broker_ws_uri(master)}) client inventory after ~#{inventory_retries} seconds")
    end
  end

  # We do *not* need to ensure we are not associated with the primary broker
  #   this requires the primary to receive socket close from the agent, which of course we have restricted above.
  #   After opening the port the broker may or may not receive the socket close making this test flaky
  #   In addition, we do not depend upon broker dis-association for any features.

end
