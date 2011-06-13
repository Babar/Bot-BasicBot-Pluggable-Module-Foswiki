use strict;
use Module::Build;

my $build = Module::Build->new(
    module_name       => "Bot::BasicBot::Pluggable::Module::Foswiki",
    license           => 'perl',
    dist_author       => q{Olivier "Babar" Raginel <babar@cpan.org>},
    dist_version_from => 'lib/Bot/BasicBot/Pluggable/Module/Foswiki.pm',
    requires      => {
        'Test::More'               => 0,
        'Bot::BasicBot::Pluggable' => '0.5',
        'Regexp::Assemble'         => 0,
        'LWP::UserAgent'           => 0,
        'HTTP::Status'             => 0,
        'URI::Title'               => 0,

    },
    add_to_cleanup => ['Bot-BasicBot-Pluggable-Module-Foswiki-*'],
);

$build->create_build_script;

