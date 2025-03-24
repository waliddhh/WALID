#!/bin/bash

# تأكد من أن السكريبت يتم تشغيله بصلاحيات root
if [ "$EUID" -ne 0 ]; then
  echo "الرجاء تشغيل هذا السكريبت باستخدام sudo."
  exit 1
fi

# تحديث الحزم وتثبيت OpenDKIM و Postfix
echo "تحديث الحزم وتثبيت Postfix و OpenDKIM..."
apt-get update -y
apt-get install -y postfix opendkim opendkim-tools

# إنشاء مجلد لمفاتيح DKIM
mkdir -p /etc/opendkim/keys

# تعيين اسم المجال (hostname) 
domain="hattam.site"

# إنشاء دليل خاص بالنطاق
mkdir -p /etc/opendkim/keys/$domain

# إنشاء مفتاح DKIM
opendkim-genkey -b 2048 -d $domain -D /etc/opendkim/keys/$domain -s default -v

# ضبط الأذونات
chown -R opendkim:opendkim /etc/opendkim
chmod -R 700 /etc/opendkim/keys/$domain

# إعداد OpenDKIM
cat > /etc/opendkim.conf <<EOL
# إعدادات OpenDKIM
Syslog                  yes
UMask                   002
Canonicalization        relaxed/simple
Mode                    sv
SubDomains              no
AutoRestart             yes
AutoRestartRate         10/1h
SignatureAlgorithm      rsa-sha256
KeyTable                refile:/etc/opendkim/key.table
SigningTable            refile:/etc/opendkim/signing.table
ExternalIgnoreList      refile:/etc/opendkim/trusted.hosts
InternalHosts           refile:/etc/opendkim/trusted.hosts
EOL

# ضبط الجداول الخاصة بـ DKIM
cat > /etc/opendkim/key.table <<EOL
default._domainkey.$domain $domain:default:/etc/opendkim/keys/$domain/default.private
EOL

cat > /etc/opendkim/signing.table <<EOL
*@${domain} default._domainkey.${domain}
EOL

cat > /etc/opendkim/trusted.hosts <<EOL
127.0.0.1
localhost
$domain
EOL

# دمج OpenDKIM مع Postfix
postconf -e "milter_default_action = accept"
postconf -e "milter_protocol = 2"
postconf -e "smtpd_milters = unix:/var/run/opendkim/opendkim.sock"
postconf -e "non_smtpd_milters = unix:/var/run/opendkim/opendkim.sock"

# التأكد من تشغيل OpenDKIM ضمن Postfix
sed -i '/SOCKET/s/^#//' /etc/default/opendkim
sed -i 's|SOCKET="local:/var/spool/postfix/opendkim.sock"|SOCKET="local:/var/run/opendkim/opendkim.sock"|' /etc/default/opendkim

# إعادة تشغيل الخدمات
systemctl restart opendkim postfix
systemctl enable opendkim postfix

# عرض مفتاح DKIM للمستخدم
echo "\nمفتاح DKIM (TXT Record) لاستخدامه في DNS:"
cat /etc/opendkim/keys/$domain/default.txt

echo "\nتم إعداد Postfix مع OpenDKIM بنجاح!"