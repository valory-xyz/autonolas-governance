module.exports = {
    "env": {
        "browser": true,
        "commonjs": true,
        "es2021": true
    },
    "extends": "eslint:recommended",
    "parserOptions": {
        "ecmaVersion": 13
    },
    "ignorePatterns": [
        "artifacts/*",
        "cache/*",
        "node_modules/*",
        "third_party/*"
    ],
    "rules": {
        "camelcase": [
            2, {
                "properties": "always"
            }
        ],
        "indent": [
            "error",
            4
        ],
        "linebreak-style": [
            "error",
            "unix"
        ],
        "quotes": [
            "error",
            "double"
        ],
        "semi": [
            "error",
            "always"
        ],
        "no-unused-vars": "warn"
    }
};
