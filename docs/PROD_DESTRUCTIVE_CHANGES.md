# Fluxo autorizado para mudancas destrutivas em producao

Este projeto bloqueia destruicao acidental de producao em duas camadas versionadas:

- `destroy.sh prod` aborta antes de carregar credenciais ou executar OpenTofu.
- `vsphere_virtual_machine.vm` gerencia somente producao e usa `lifecycle.prevent_destroy = true`.

Enquanto o bloco `prevent_destroy` estiver presente, `tofu destroy` e planos que exigem substituicao destrutiva da VM de producao devem falhar. `dev` e `homolog` usam `vsphere_virtual_machine.vm_nonprod` e continuam destrutiveis pelo fluxo normal de `destroy.sh`.

## Quando usar excecao

Use este fluxo apenas quando a mudanca realmente exigir destruir, substituir ou remover do state uma VM de producao. Mudancas in-place de producao continuam pelo fluxo normal de `./apply.sh prod`, com revisao do plano.

## Fluxo break-glass

1. Abrir PR explicito descrevendo o recurso de producao afetado, motivo, janela operacional e plano de retorno.
2. Incluir no PR o plano esperado e evidencias de que o escopo nao afeta `dev` ou `homolog`.
3. Obter aprovacao da equipe responsavel pela infraestrutura e da operacao do servico afetado.
4. Durante a janela aprovada, remover temporariamente `prevent_destroy = true` apenas do recurso de producao estritamente necessario.
5. Executar `tofu plan` com `backend/prod.s3.tfbackend`, workspace `PRODUCTION` e `env_vars/prod.tfvars`; revisar que o plano contem somente o alvo aprovado.
6. Aplicar somente o plano revisado.
7. Restaurar imediatamente `prevent_destroy = true` no mesmo PR ou em PR de follow-up bloqueante antes de encerrar a janela.
8. Registrar resultado, horario, operador, plano aplicado e link da mudanca.

## Regras que nao devem ser quebradas

- Nao usar `destroy.sh` para producao.
- Nao migrar state de producao para `vsphere_virtual_machine.vm_nonprod`.
- Nao deixar `prevent_destroy = false` versionado.
- Nao remover o bloco do recurso de producao sem aprovacao explicita.
- Nao aplicar plano salvo que nao tenha sido revisado dentro da janela aprovada.

## Recuperacao de guardrail

Se o guardrail for removido para uma excecao, a proxima mudanca obrigatoria e restaurar:

```hcl
lifecycle {
  ignore_changes = [
    extra_config,
    annotation
  ]
  prevent_destroy = true
}
```

O CI `Prod safety guardrails` falha enquanto a protecao nao estiver restaurada.
