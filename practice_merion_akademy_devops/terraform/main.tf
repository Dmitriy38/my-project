/*
Данный блок используется для инициализации локального терраформ провайдера 
Для проверки корректности выполните:
terraform init
*/


terraform {
  #блок с подключаемыми провайдерами
  required_providers {
    #название провайдера
    hashicups = {
      #версия провайдера
      version = "~> 0.3.1"
      #путь до него
      source = "hashicorp.com/edu/hashicups"
    }
  }
}


#блок с описанием провайдера
#в блоке описываются настройки провайдера, а так же
#настройки пользователя, который будет осуществлять взаимодействие с системой
provider "hashicups" {
  #имя пользователя
  username = "student"
  #пароль пользователя
  password = "test123"
}


#получение списка кофе
data "hashicups_coffees" "coffees" {
  #без параметров
}


#заказ кофе, состоит из списка кофе
data "hashicups_order" "order_info" {
  #если заказов нет - пустой список
  id = hashicups_order.order.id
}


#блок создания, редактирования заказа
resource "hashicups_order" "order" {
  #блок, описывающий заказ
  items {
    coffee {
      #id кофе
      id = 3
    }
    #кол-во кофе
    quantity = 5
  }


  items {
    coffee {
      id = 2
    }
    quantity = 2
  }


}


output "test_order_info" {
  value = data.hashicups_order.order_info
}


output "test_order" {
  value = hashicups_order.order
}

output "test_coffees" {
  value = data.hashicups_coffees.coffees
}

