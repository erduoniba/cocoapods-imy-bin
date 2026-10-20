require File.expand_path('../../spec_helper', __FILE__)

module Pod
  describe Command::Bin do
    describe 'CLAide' do
      it 'registers it self' do
        Command.parse(%w{ bin }).should.be.instance_of Command::Bin
      end

      it 'registers publishing and component switching' do
        Command.parse(%w{ bin publish Foo.podspec }).should.be.instance_of Command::Bin::Publish
        Command.parse(%w{ bin switch Foo source --no-install }).should.be.instance_of Command::Bin::Switch
        Command.parse(%w{ bin sync SampleApp }).should.be.instance_of Command::Bin::Sync
      end
    end
  end
end
