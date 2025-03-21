# How to setup the application

## First-time fresh install

### Database initialization
1. Point your web browser to `<YOUR_HOST>/install` or `<YOUR_HOST>/<YOUR_PATH>/install`
(if you are using a custom URL-path)
   - Enter the installation password (docker variable `LB_INSTALL_PWD`)
   - Enter the database root user: `root`
   - Enter the database root password (docker variable `LB_DB_USER_PWD`)
   - Select `Create the database`
   - Select `Create the database user`
   - Click on the register link, at the bottom of the web page
   - Fill the register form for the application administrator
   - Click on the button `Register`

### Application configuration
1. Point your web browser to `<YOUR_HOST>` or `<YOUR_HOST>/<YOUR_PATH>`
if you are using a reverse-proxy
1. Login with your application administrator profile
1. Configure the web application

## Upgrade from a previous application version
1. Stop the service
   ```
   docker-compose down
   ```
1. Change the image name inside your `docker-compose.yml` file
1. Restart the service
   ```
   docker-compose up --detach
   ```
1. Upgrade the application database by accessing `<YOUR_HOST>/install/configure.php`
or `<YOUR_HOST>/<YOUR_PATH>/install/configure.php`
