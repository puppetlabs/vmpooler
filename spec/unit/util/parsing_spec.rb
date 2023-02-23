require 'spec_helper'

# The only method previously tested here was '#get_domain_for_pool'
# which was moved to Vmpooler::Dns as the more appropriate class
#
# TODO: Add tests for last remaining method, or move to more appropriate class
describe 'Vmpooler::Parsing' do
  let(:pool) { 'pool1' }
  subject { Vmpooler::Parsing }

end
