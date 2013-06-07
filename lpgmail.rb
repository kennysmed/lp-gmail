$LOAD_PATH.unshift(File.dirname(__FILE__))
$stdout.sync = true

require 'thin'
require 'lpgmail/frontend'

raise 'GOOGLE_CLIENT_ID is not set' if !ENV['GOOGLE_CLIENT_ID']
raise 'GOOGLE_CLIENT_SECRET is not set' if !ENV['GOOGLE_CLIENT_SECRET']


LpGmail::Frontend.run!
