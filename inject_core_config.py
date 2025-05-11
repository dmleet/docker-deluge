#!/usr/bin/python3

import os
import logging
import re
logging.basicConfig(level=logging.DEBUG)
from deluge.config import Config
from deluge.core.preferencesmanager import DEFAULT_PREFS as CORE_CONFIG_DEFAULTS

envNamePrefix = "DELUGE_CONF_CORE_"
configDir = '/home/deluge/.config/deluge'
configFileName = 'core.conf'
configPath = configDir + '/' + configFileName

if os.path.isfile(configPath):
    logging.info("Config file (%s) found, skipping defaults" % configPath)
    defaults = None
else:
    logging.info("Config file (%s) not found, loading defaults" % configPath)
    defaults = CORE_CONFIG_DEFAULTS

logging.info("Reading %s" % configFileName)
config = Config(configFileName, defaults, configDir)

for param in os.environ.keys():
    if param.startswith(envNamePrefix):
        propertyName = param[len(envNamePrefix):].lower()
        propertyValue = os.environ[param]
        if propertyValue.lower() in ("true", "yes"):
            propertyValue = True
        elif propertyValue.lower() in ("false", "no"):
            propertyValue = False
        elif re.match(r'^\[.*\]$', propertyValue):
            propertyValue = propertyValue[1:-1].split(',')

        logging.debug("Injecting %s = %s" % (propertyName, propertyValue))
        config[propertyName] = propertyValue

# For deployment using kubernetes stateful set
# Dynamically set incoming port based on pod name
if 'POD_NAME' in os.environ:
    base_port = 61534
    pod_name = os.getenv('POD_NAME')
    match = re.match(r'.*-(\d+)$', pod_name)
    if match:
        pod_index = int(match.group(1))
        listen_port = base_port + pod_index
        config["listen_ports"] = [listen_port, listen_port]
        logging.info(f"Assigned listen port {listen_port} for pod {pod_name}")
    else:
        logging.warning(f"POD_NAME found but did not match expected pattern: {pod_name}")
else:
    logging.info("POD_NAME not set; using default listen ports")

logging.info("Saving merged %s" % configFileName)
config.save(configPath)