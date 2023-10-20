all: dhcpd named

named:
	/root/make-namedb.sh

dhcpd:
	/root/make-dhcpd > /usr/local/etc/dhcpd.conf

reload:
	service named reload
	service isc-dhcpd reload

restart:
	service named restart
	service isc-dhcpd restart
