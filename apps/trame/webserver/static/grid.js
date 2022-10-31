/* from vuejs.org/examples/#grid */
export default {
  props: {
    data: Array,
    columns: Array,
    loadingText: String,
  },
  methods: {
    visualize(item) {
      console.log("visualize", item.name, item.container)
      this.$emit('view', item.name, item.container)
    },
  },
  template: `
    <v-data-table disable-filtering disable-pagination hide-default-footer
      loading=true
      loading-text="no datasets present"
      :headers="columns"
      :items="data">
      <template v-slot:item.actions="{ item }">
        <v-icon
          small
          class="mr-2"
          @click="visualize(item)"
        >
          mdi-cube-scan
        </v-icon>
      </template>
    </v-data-table>
  `
}