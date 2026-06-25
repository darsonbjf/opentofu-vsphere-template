#!/bin/bash

# Obter o ID da categoria existente
CATEGORY_ID=$(govc tags.category.ls -json | jq -r '.[] | select(.name=="ambiente") | .id')

if [ -n "$CATEGORY_ID" ]; then
    echo "Importando categoria existente com ID: $CATEGORY_ID"
    tofu import "vsphere_tag_category.environment" "$CATEGORY_ID"
else
    echo "Categoria 'ambiente' não encontrada"
    exit 1
fi
