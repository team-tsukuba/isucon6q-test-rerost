system-reload:
  sudo nginx -s reload
  sudo systemctl restart isuda.ruby.service isutar.ruby.service

service-reload:
  sudo systemctl restart isuda.ruby.service isutar.ruby.service
