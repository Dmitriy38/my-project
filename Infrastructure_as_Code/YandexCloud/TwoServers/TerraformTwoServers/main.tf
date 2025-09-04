terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  token     = var.token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = "ru-central1-a"
}

data "yandex_compute_image" "my-ubuntu-2004-1" {
  family = "ubuntu-2004-lts"
}

resource "yandex_compute_instance" "my-vm-2" {
  name        = "test-vm-2"
  platform_id = "standard-v1"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "${data.yandex_compute_image.my-ubuntu-2004-1.id}"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.my-sn-1.id
    nat = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }
}

resource "yandex_compute_instance" "my-vm-3" {
  name        = "test-vm-3"
  platform_id = "standard-v1"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "${data.yandex_compute_image.my-ubuntu-2004-1.id}"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.my-sn-1.id
    nat = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }
}

resource "yandex_vpc_network" "default" {
  name = "my-nw-2"
}

resource "yandex_vpc_subnet" "my-sn-1" {
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.default.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

resource "yandex_lb_target_group" "my-lb-tg-1" {
  name      = "my-target-group-1"
  region_id = "ru-central1"

  target {
    subnet_id = "${yandex_vpc_subnet.my-sn-1.id}"
    address   = "${yandex_compute_instance.my-vm-2.network_interface.0.ip_address}"
  }

  target {
    subnet_id = "${yandex_vpc_subnet.my-sn-1.id}"
    address   = "${yandex_compute_instance.my-vm-3.network_interface.0.ip_address}"
  }
}

resource "yandex_lb_network_load_balancer" "my-nw-lb-1" {
  name = "my-network-load-balancer-1"

  listener {
    name = "my-listener-1"
    port = 80
  }

  attached_target_group {
    target_group_id = "${yandex_lb_target_group.my-lb-tg-1.id}"

    healthcheck {
      name = "http"
      http_options {
        port = 80
      }
    }
  }
}

output "internal_ip_address_vm_2" {
  value = yandex_compute_instance.my-vm-2.network_interface.0.ip_address
}

output "external_ip_address_vm_2" {
  value = yandex_compute_instance.my-vm-2.network_interface.0.nat_ip_address
}

output "internal_ip_address_vm_3" {
  value = yandex_compute_instance.my-vm-3.network_interface.0.ip_address
}

output "external_ip_address_vm_3" {
  value = yandex_compute_instance.my-vm-3.network_interface.0.nat_ip_address
}

output "my_balancer_ip_address" {
  value = yandex_lb_network_load_balancer.my-nw-lb-1.listener
}
