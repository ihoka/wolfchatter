# Nominatim usage policy requires an identifying User-Agent and at most one
# request per second. The throttle (seconds between calls) is read by the job
# that calls ReverseGeocoder. Environment files may override these first.
Rails.application.config.x.nominatim.user_agent ||= "Wolfchatter/1.0 (+https://github.com/ihoka/wolfchatter)"
Rails.application.config.x.nominatim.throttle ||= 1.0
