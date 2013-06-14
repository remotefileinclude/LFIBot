---
servers:
  'whatnet':
    host: 'irc.whatnet.org' 
    port: 6667
    admins: [  ]
    blacklist: [  ]
    channels: [ '#bottesting' ]
    do_auth: 1
    throttle: 3
    cmd_prefix: '.'
    auth_handlers:
      auth_service: 'H'
      auth_string_t: 'AUTH ##user## ##password##'
      auth_success: 'I recognize you'
      auth_failure: 'Incorrect password; please try again.'
      ask_if_authed: 'userinfo ##user_authed##'
      user_authed: '([^\s]+) is authenticated to account ([^\s]+)\.'
      user_not_authed: 'user with nick ([^\s]+) does not exist'
    nick: 'lfi'
    ircname: 'lfi-bot'
    user: '##USER##'
    password: '##PASSWORD##' 
    data_file: '/tmp/lfibot.db'
    quit_message: "I'm about to break"
    modules: 
      - 'LinkHistory'
      - 'UrbanDictionary'
      - 'KOTH'
