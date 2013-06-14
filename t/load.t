use local::lib;
use Test::More tests => 11;

BEGIN {
    use_ok('LFIBot');
    use_ok('LFIBot::Session');
    use_ok('LFIBot::Handlers');
    use_ok('LFIBot::Commands');
    use_ok('LFIBot::AdminCommands');
    use_ok('LFIBot::Triggers');
    use_ok('LFIBot::Logger'); 
    use_ok('LFIBot::Startup');
    use_ok('LFIBot::Plugins::LinkHistory');
    use_ok('LFIBot::Plugins::UrbanDictionary');
    use_ok('LFIBot::Plugins::KOTH'); 
    use_ok('LFIBot::Plugin');
}
