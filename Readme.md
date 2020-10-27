Dependencies

**Install the "html2slim" gem**

gem install html2slim


**Install nodejs**

sudo apt-get install nodejs


**Install yarn**

sudo apt remove cmdtest

curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -

echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list

sudo apt update && sudo apt install yarn

yarn --version


**Setup mysql access**

The current use should have admin access to the mysql server via .my.cnf so that it can create the appropriate dev and test databases

Edit the app name and the expected final url
APP_NAME = "raft"
SITE_URL = "https://www.example.com"

Cleaning up mysql database in case of failure
drop database baf3_test;
drop database baf3_dev;
drop database baf3_prod;
drop user baf3;

