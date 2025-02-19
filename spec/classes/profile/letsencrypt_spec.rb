require "spec_helper"

# TODO: track with updatecli
certbot_version = "3.1.0"
# TODO: track with updatecli
certbot_dns_azure_version = "2.6.1"

describe "profile::letsencrypt" do
  context "default setup uses HTTP-01 with staging" do
    it {
      expect(subject).to contain_package("python3.10")
      expect(subject).to contain_package("python3-pip")
      expect(subject).to contain_package("libaugeas0")

      expect(subject).to contain_exec("Install certbot").with({
        :command => "/usr/bin/python3.10 -m pip install --upgrade certbot==#{certbot_version}",
      })

      expect(subject).to contain_exec("Install certbot-apache plugin").with({
        :command => "/usr/bin/python3.10 -m pip install --upgrade --use-pep517 certbot-apache==#{certbot_version}",
        :unless => "/usr/bin/python3.10 -m pip list | /bin/grep --word-regexp certbot-apache | /bin/grep #{certbot_version}",
      })

      expect(subject).to contain_class("letsencrypt").with_config({
        "email" => "tyler@monkeypox.org",
        "server" => "https://acme-staging-v02.api.letsencrypt.org/directory",
        "authenticator" => "apache",
        "preferred-challenges" => "http",
        "deploy-hook" => "systemctl reload apache2",
      }).with_package_ensure("absent").with_configure_epel(false)
      expect(subject).to contain_file("/etc/letsencrypt/azure.ini").with({
        :ensure => "absent",
      })
      expect(subject).to contain_cron("certbot-renew-all").with({
        :command => "bash -c 'date && /usr/local/bin/certbot renew' >>/var/log/certbot-renew-all.log 2>&1",
        :user => "root",
        :hour => 6,
      })
    }
  end

  context "custom setup with Azure DNS-01 challenge and production environment" do
    let(:environment) { "production" }
    let(:params) do
      {
        :plugin => "dns-azure",
        :dns_azure => {
          :sp_client_id => "sp-app-id",
          :sp_client_secret => "token",
          :tenant_id => "tenant-id",
          :zones => {
            :localhost => "/subscriptions/xxx/AzureDNS/localhost",
            :"app.localhost" => "/subscriptions/xxx/AzureDNS/localhost",
          },
        },
      }
    end

    it {
      expect(subject).to contain_package("python3.10")
      expect(subject).to contain_package("python3-pip")

      expect(subject).to contain_exec("Install certbot").with({
        :command => "/usr/bin/python3.10 -m pip install --upgrade certbot==#{certbot_version}",
      })

      expect(subject).not_to contain_exec("Install certbot-apache plugin").with({
        :command => "/usr/bin/python3.10 -m pip install --upgrade certbot-apache==#{certbot_version}",
      })

      expect(subject).to contain_exec("Install certbot-dns-azure plugin").with({
        :command => "/usr/bin/python3.10 -m pip install --upgrade certbot-dns-azure==#{certbot_dns_azure_version}",
        :unless => "/usr/bin/python3.10 -m pip list | /bin/grep --word-regexp certbot-dns-azure | /bin/grep #{certbot_dns_azure_version}",
      })

      expect(subject).to contain_file("/etc/letsencrypt/azure.ini").with({
        :ensure => "file",
        :owner => "root",
        :group => "root",
        :mode => "0600",
      })
      expect(subject).to contain_class("letsencrypt").with_config({
        "email" => "tyler@monkeypox.org",
        "server" => "https://acme-v02.api.letsencrypt.org/directory", # Due to production environment set up
        "authenticator" => "dns-azure",
        "preferred-challenges" => "dns",
        "dns-azure-config" => "/etc/letsencrypt/azure.ini",
        "deploy-hook" => "systemctl reload apache2",
      }).with_package_ensure("absent").with_configure_epel(false)
    }

    it "should specify the custom config + DNS-01 setup for letsencrypt" do
      expect(subject).to contain_class("letsencrypt")
    end
  end
end
