system-reload:
	make nginx-reload
	make service-reload

service-reload:
	sudo systemctl restart isuda.ruby.service isutar.ruby.service

nginx-reload:
	sudo nginx -s reload
