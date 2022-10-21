#!/usr/bin/env bash

# Set up eZ configuration.
# Requires composer dependencies to have been set up already.
#
# Uses env vars: EZ_VERSION, EZ_BUNDLES, EZ_LEGACY_EXTENSIONS, EZ_TEST_CONFIG_SYMFONY, EZ_TEST_CONFIGS_LEGACY

# @todo check if all required vars have a value
# @todo replace this with a php script? It is starting to be a mess...
# @todo make this work when SF env to run tests on is not 'behat'

set -e

echo "Setting up eZ configuration..."

source "$(dirname "$(dirname -- "${BASH_SOURCE[0]}")")/set-env-vars.sh"

INSTALL_LEGACY_BRIDGE=false

STACK_DIR="$(dirname -- "$(dirname -- "$(dirname -- "${BASH_SOURCE[0]}")")")"

if [ "${EZ_VERSION}" = "ezplatform3" ]; then
    APP_DIR=vendor/ezsystems/ezplatform
    CONFIG_DIR="${APP_DIR}/config"
elif [ "${EZ_VERSION}" = "ezplatform2" ]; then
    APP_DIR=vendor/ezsystems/ezplatform
    CONFIG_DIR="${APP_DIR}/app/config"
elif [ "${EZ_VERSION}" = "ezplatform" ]; then
    APP_DIR=vendor/ezsystems/ezplatform
    CONFIG_DIR="${APP_DIR}/app/config"
elif [ "${EZ_VERSION}" = "ezpublish-community" ]; then
    APP_DIR=vendor/ezsystems/ezpublish-community
    CONFIG_DIR="${APP_DIR}/ezpublish/config"
else
    printf "\n\e[31mERROR:\e[0m unsupported eZ version '${EZ_VERSION}'\n\n" >&2
    exit 1
fi

# hopefully these bundles will stay there :-) it is important that they are loaded after the kernel ones...
if [ "${EZ_VERSION}" = "ezplatform3" ]; then
    LAST_BUNDLE='Lexik\\Bundle\\JWTAuthenticationBundle\\LexikJWTAuthenticationBundle'
elif [ "${EZ_VERSION}" = "ezplatform" -o "${EZ_VERSION}" = "ezplatform2" ]; then
    LAST_BUNDLE=AppBundle
else
    LAST_BUNDLE=OneupFlysystemBundle
fi

# eZ5/eZPlatform config files
if [ -f "${CONFIG_DIR}/parameters.yml.dist" ]; then
    cp "${CONFIG_DIR}/parameters.yml.dist" "${CONFIG_DIR}/parameters.yml"
fi
if [ -f "${STACK_DIR}/config/${EZ_VERSION}/config_behat.yml" ]; then
    # @todo if config_behat_orig.yml exists, rename it as well
    grep -q 'config_behat_orig.yml' "${CONFIG_DIR}/config_behat.yml" || mv "${CONFIG_DIR}/config_behat.yml" "${CONFIG_DIR}/config_behat_orig.yml"
    cp "${STACK_DIR}/config/${EZ_VERSION}/config_behat.yml" "${CONFIG_DIR}/config_behat.yml"
fi
cp "${STACK_DIR}/config/common/config_behat.php" "${CONFIG_DIR}/config_behat.php"
if [ -f "${STACK_DIR}/config/${EZ_VERSION}/ezpublish_behat.yml" ]; then
    grep -q 'ezpublish_behat_orig.yml' "${CONFIG_DIR}/ezpublish_behat.yml" || mv "${CONFIG_DIR}/ezpublish_behat.yml" "${CONFIG_DIR}/ezpublish_behat_orig.yml"
    cp "${STACK_DIR}/config/${EZ_VERSION}/ezpublish_behat.yml" "${CONFIG_DIR}/ezpublish_behat.yml"
fi
# only for ezplatform3
if [ -f "${STACK_DIR}/config/${EZ_VERSION}/ezplatform.yml" ]; then
    grep -q 'ezplatform_orig.yml' "${CONFIG_DIR}/packages/behat/ezplatform.yaml" || mv "${CONFIG_DIR}/packages/behat/ezplatform.yaml" "${CONFIG_DIR}/packages/behat/ezplatform_orig.yaml"
    cp "${STACK_DIR}/config/${EZ_VERSION}/ezplatform.yml" "${CONFIG_DIR}/packages/behat/ezplatform.yaml"
fi

if [ -n "${EZ_TEST_CONFIG_SYMFONY}" ]; then
    # @todo allow .xml and .php besides .yml
    if [ -f "${CONFIG_DIR}/config_behat_bundle.yml" -o -L "${CONFIG_DIR}/config_behat_bundle.yml" ]; then
        rm "${CONFIG_DIR}/config_behat_bundle.yml"
    fi
    ln -s "$(realpath ${EZ_TEST_CONFIG_SYMFONY})" "${CONFIG_DIR}/config_behat_bundle.yml"
    #sed -i "/# placeholder for extra configuration files/- { resource: '${}' }" ${CONFIG_DIR}/config_behat.yml
else
    if [ -L "${CONFIG_DIR}/config_behat_bundle.yml" ]; then
        rm "${CONFIG_DIR}/config_behat_bundle.yml"
    fi
    echo "# This file is automatically generated by ez-config.sh" > "${CONFIG_DIR}/config_behat_bundle.yml"
    echo "# It is replaced by a symlink to a yaml file with settings useful for running tests when the env var EZ_TEST_CONFIG_SYMFONY is set" >> "${CONFIG_DIR}/config_behat_bundle.yml"
fi

# Load the custom bundles in the Sf kernel
for BUNDLE in ${EZ_BUNDLES}; do
    if [ "${BUNDLE}" = 'eZ\Bundle\EzPublishLegacyBundle\EzPublishLegacyBundle' ]; then
        ARG='$this'
        INSTALL_LEGACY_BRIDGE=true
    else
        ARG=
    fi
    if [ -f "${CONFIG_DIR}/bundles.php" ]; then
        if ! fgrep -q "${BUNDLE}::class  => ['all' => true]," "${CONFIG_DIR}/bundles.php"; then
            BUNDLE=${BUNDLE//\\/\\\\}
            sed -i "/${LAST_BUNDLE}::class *=> *\[/i ${BUNDLE}::class => \['all' => true\]," "${CONFIG_DIR}/bundles.php"
        fi
    else
        if ! fgrep -q "new ${BUNDLE}(${ARG})" "${KERNEL_DIR}/${KERNEL_CLASS}.php"; then
            BUNDLE=${BUNDLE//\\/\\\\}
            sed -i "/${LAST_BUNDLE}()/i new ${BUNDLE}(${ARG})," "${KERNEL_DIR}/${KERNEL_CLASS}.php"
        fi
    fi
done

# Fix the eZ5/eZPlatform autoload configuration for the unexpected directory layout
if [ -f "${KERNEL_DIR}/autoload.php" ]; then
    sed -i "s#'/../vendor/autoload.php'#'/../../../../vendor/autoload.php'#" "${KERNEL_DIR}/autoload.php"
fi

# and the one for eZPlatform 3
if [ -f "${CONFIG_DIR}/bootstrap.php" ]; then
  sed -i "s#dirname(__DIR__).'/vendor/autoload.php'#dirname(__DIR__).'/../../../vendor/autoload.php'#" "${CONFIG_DIR}/bootstrap.php"
fi

# as well as the config for jms_translation
# @todo can't we just override these values instead of hacking the original files?
if [ -f "${CONFIG_DIR}/config.yml" ]; then
    sed -i "s#'%kernel.root_dir%/../vendor/ezsystems/ezplatform-admin-ui/src#'%kernel.root_dir%/../../ezplatform-admin-ui/src#" ${CONFIG_DIR}/config.yml
    sed -i "s#'%kernel.root_dir%/../vendor/ezsystems/ezplatform-admin-ui-modules/src#'%kernel.root_dir%/../../ezplatform-admin-ui-modules/src#" ${CONFIG_DIR}/config.yml
fi
if [ -f "${CONFIG_DIR}/packages/ezplatform_admin_ui.yaml" ]; then
    sed -i "s#'%kernel.project_dir%/vendor/ezsystems/ezplatform-admin-ui/src#'%kernel.project_dir%/../ezplatform-admin-ui/src#" ${CONFIG_DIR}/packages/ezplatform_admin_ui.yaml
    #sed -i "s#'%kernel.project_dir%/vendor/ezsystems/ezplatform-admin-ui/src/bundle/Resources/translations/#'%kernel.root_dir%/../../ezplatform-admin-ui/src/bundle/Resources/translations/#" ${CONFIG_DIR}/packages/ezplatform_admin_ui.yaml
fi

if [ "${EZ_VERSION}" = "ezplatform3" ]; then
    # 1. registration of services from ezplatform/config/services_behat.yml -> use an sf env which is neither test nor behat or avoid including it
    if [ -f "${CONFIG_DIR}/services_behat.yaml" ]; then
        mv "${CONFIG_DIR}/services_behat.yaml" "${CONFIG_DIR}/services_behat.yaml.orig"
    fi
    # 2. EzSystemsEzPlatformGraphQLExtension::PACKAGE_DIR_PATH or the derived ezplatform.graphql.schema.fields_definition_file, ezplatform.graphql.package.root_dir
    sed -i "s#const PACKAGE_DIR_PATH = '/vendor/ezsystems/ezplatform-graphql'#const PACKAGE_DIR_PATH = '/../../../vendor/ezsystems/ezplatform-graphql'#" vendor/ezsystems/ezplatform-graphql/src/DependencyInjection/EzSystemsEzPlatformGraphQLExtension.php
    # 3. Symfony\Bridge\ProxyManager\LazyProxy\PhpDumper\LazyLoadingValueHolderGenerator to move from Zend\Code\Generator\ClassGenerator to Laminas
    sed -i 's#use Zend\\Code\\Generator\\ClassGenerator;#use Laminas\\Code\\Generator\\ClassGenerator;#' vendor/symfony/proxy-manager-bridge/LazyProxy/PhpDumper/LazyLoadingValueHolderGenerator.php
    # 4. hack InstallPlatformCommand.php, change $console = escapeshellarg('bin/console');  and friends
    sed -i "s#escapeshellarg('bin/console')#escapeshellarg('vendor/ezsystems/ezplatform/bin/console')#" vendor/ezsystems/ezplatform-kernel/eZ/Bundle/PlatformInstallerBundle/src/Command/InstallPlatformCommand.php
    sed -i "s#escapeshellarg('bin/console')#escapeshellarg('vendor/ezsystems/ezplatform/bin/console')#" vendor/ezsystems/ezplatform-kernel/eZ/Bundle/EzPublishCoreBundle/Features/Context/ConsoleContext.php
    sed -i "s#escapeshellarg('bin/console')#escapeshellarg('vendor/ezsystems/ezplatform/bin/console')#" vendor/ezsystems/behatbundle/src/bundle/Command/CreateExampleDataManagerCommand.php
    # 5. create dir ./public
    if [ ! -d public/var ]; then
        mkdir -p public/var
    fi

    # - TranslationResourceFilesPass::getTranslationFiles (line 58) - or find out why the 3d param to translator.default service has not been replaced
    # - doctrine / dbal / url set in (???)
    # - hack behatbundle's file stages.yaml to disable EzSystems\Behat\Subscriber\PublishInTheFuture
    # - hack behat/ezplatform_orig.yml, comment out line ezplatform.behat.enable_enterprise_services: true - it seems that we can not override that param in our own behat/ezplatform.yml ?
fi

# Fix the eZ console autoload config if needed (ezplatform 2 and ezplatform 3)
if [ -f "${APP_DIR}/bin/console" ]; then
    sed -i "s#'/../vendor/autoload.php'#'/../../../../vendor/autoload.php'#" "${APP_DIR}/bin/console"
    sed -i "s#dirname(__DIR__).'/vendor/autoload.php'#dirname(__DIR__).'/../../../vendor/autoload.php'#" "${APP_DIR}/bin/console"
fi

# Set up config related to LegacyBridge if needed
# @see https://github.com/ezsystems/LegacyBridge/blob/1.5/INSTALL-MANUALLY.md
if [ "${INSTALL_LEGACY_BRIDGE}" = true ]; then
    if [ -f "${CONFIG_DIR}/config_legacy_bridge.yml" -o -L "${CONFIG_DIR}/config_legacy_bridge.yml" ]; then
        rm "${CONFIG_DIR}/config_legacy_bridge.yml"
    fi
    ln -s "$(realpath ${STACK_DIR}/config/legacy-bridge/config_legacy_bridge.yml)" "${CONFIG_DIR}/config_legacy_bridge.yml"

    if ! grep -E -q "^ +resource *: *['\"]@EzPublishLegacyBundle/Resources/config/routing.yml['\"]" "${CONFIG_DIR}/routing.yml" ; then
        echo '_ezpublishLegacyRoutes:' >> "${CONFIG_DIR}/routing.yml"
        echo "    resource: '@EzPublishLegacyBundle/Resources/config/routing.yml'" >> "${CONFIG_DIR}/routing.yml"
    fi
else
    if [ -L "${CONFIG_DIR}/config_legacy_bridge.yml" ]; then
        rm "${CONFIG_DIR}/config_legacy_bridge.yml"
    fi
    echo "# This file is automatically generated by ez-config.sh" > "${CONFIG_DIR}/config_legacy_bridge.yml"
    echo "# It is replaced by a symlink to a yaml file with settings required by the Legacy Bridge when required" >> "${CONFIG_DIR}/config_legacy_bridge.yml"
fi

# Set up config for ezpublish-community
if [ "${EZ_VERSION}" = "ezpublish-community" ]; then
    cat "${STACK_DIR}/config/ezpublish-legacy/config.php" > vendor/ezsystems/ezpublish-legacy/config.php
fi

if [ "${EZ_VERSION}" = "ezpublish-community" -o "${INSTALL_LEGACY_BRIDGE}" = true ]; then

    "${STACK_DIR}/bin/sfconsole.sh" ezpublish:legacybundles:install_extensions --force

    # If top-level project is an extension, symlink it
    # We use the same test as LegacyBundleInstallCommand
    if [ -f ezinfo.php -o -f extension.xml ]; then
        # There's no good way to know the name of the extension, so we assume it is the first in the list
        ARR=($EZ_LEGACY_EXTENSIONS)
        EXTENSION=${ARR[0]}
        if [ ! -L "vendor/ezsystems/ezpublish-legacy/extension/${EXTENSION}" -a ! -d "vendor/ezsystems/ezpublish-legacy/extension/${EXTENSION}" ]; then
            # @todo print a warning if target extension exists and is a dir instead of a symlink, or a symlink with wrong target
            ln -s $(realpath .) "vendor/ezsystems/ezpublish-legacy/extension/${EXTENSION}"
        fi
    fi

    # If top-level project is a bundle with extensions, symlink them
    if [ -d ezpublish_legacy ]; then
        for EXTENSION in $(ls ezpublish_legacy); do
            if [ -d "ezpublish_legacy/${EXTENSION}" ]; then
                if [ ! -L "vendor/ezsystems/ezpublish-legacy/extension/${EXTENSION}" -a ! -d "vendor/ezsystems/ezpublish-legacy/extension/${EXTENSION}" ]; then
                    # @todo print a warning if target extension exists and is a dir instead of a symlink, or a symlink with wrong target
                    ln -s $(realpath "ezpublish_legacy/${EXTENSION}") "vendor/ezsystems/ezpublish-legacy/extension/${EXTENSION}"
                fi
            fi
        done
    fi

    # Set up minimal legacy settings
    # Note: these are slightly different from the ones coming with the stock Legacy Bridge...
    cp -r ${STACK_DIR}/config/ezpublish-legacy/init_ini/* vendor/ezsystems/ezpublish-legacy/settings/
    if [ "${INSTALL_LEGACY_BRIDGE}" = true ]; then
        sed -i "s/#Charset=utf8mb4#/Charset=utf8mb4/" vendor/ezsystems/ezpublish-legacy/settings/override/site.ini.append.php
    fi

    # Enable legacy extensions
    for EXTENSION in ${EZ_LEGACY_EXTENSIONS}; do
        if ! grep -q "^ActiveExtensions\[\]=${EXTENSION}$" vendor/ezsystems/ezpublish-legacy/settings/override/site.ini.append.php; then
            sed -i "0,/^ActiveExtensions\[\]$/{s/^ActiveExtensions\[\]$/&\nActiveExtensions\[\]=${EXTENSION}/}" vendor/ezsystems/ezpublish-legacy/settings/override/site.ini.append.php
        fi
    done

    # generate legacy autoloads
    ${STACK_DIR}/bin/sfconsole.sh ezpublish:legacy:script bin/php/ezpgenerateautoloads.php

    # @todo allow end user to specify legacy settings & design items when running with ezpublish-community or legacy-bridge
fi

# Fix the phpunit configuration if needed
# @todo is this needed any more ? it is not in kaliop ezmigrationbundle's phpunit.xml.dist...
if [ -f phpunit.xml.dist ]; then
    if [ "${EZ_VERSION}" = "ezplatform" -o "${EZ_VERSION}" = "ezplatform2" ]; then
        sed -i 's/"vendor\/ezsystems\/ezpublish-community\/ezpublish"/"vendor\/ezsystems\/ezplatform\/app"/' phpunit.xml.dist
    elif [ "${EZ_VERSION}" = "ezplatform3" ]; then
        sed -i 's/"vendor\/ezsystems\/ezpublish-community\/ezpublish"/"vendor\/ezsystems\/ezplatform\/src"/' phpunit.xml.dist
    fi
fi

# @todo why is there a problem with vendor/ezsystems/ezplatform/config/services_behat.yaml ?

echo Done
