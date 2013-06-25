$LOAD_PATH.unshift(File.dirname(__FILE__))
$stdout.sync = true

require 'thin'
require 'lpgmail/frontend'

LpGmail::Frontend.run!
