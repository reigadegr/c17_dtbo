
lfdtget=$MODPATH/bin/fdtget
lfdtput=$MODPATH/bin/fdtput

for i in $($lfdtget $1 /__fixups__ soc); do
    local lpath=$(echo $i | sed 's/\:target\:0//g')
    if $lfdtget -l $1 ${lpath}/__overlay__ | grep -q hmbird; then
        $lfdtput -t s $1 ${lpath}/__overlay__/oplus,hmbird/version_type type HMBIRD_GKI
		ui_print "- 读出补丁字符串: $($lfdtget $1 ${lpath}/__overlay__/oplus,hmbird/version_type type)"
        break
    fi
done
